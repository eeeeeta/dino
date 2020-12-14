using Gee;

using Xmpp;
using Xmpp.Xep;
using Dino.Entities;
using Qlite;

namespace Dino {

public class MamManager : StreamInteractionModule, Object {
       public static ModuleIdentity<MamManager> IDENTITY = new ModuleIdentity<MamManager>("mam_manager");
       public string id { get { return IDENTITY.id; } }

    public signal void mam_start(Account id, string jid, string query_id);
    public signal void mam_stop(Account id, string jid, string query_id);

    private StreamInteractor stream_interactor;
    private HashMap<string, DateTime> mam_times = new HashMap<string, DateTime>();
    private HashMap<string, long> mam_counts = new HashMap<string, long>();
    public HashMap<string, string> mam_inflight = new HashMap<string, string>();
    private Database db;
    private int stanzas_synced;


    private MamManager(StreamInteractor stream_interactor, Database db) {
            warning("MAM MANAGER()");
            this.stream_interactor = stream_interactor;
            this.db = db;
        stream_interactor.account_added.connect(on_account_added);
    }

public int num_inflight() {
       return this.mam_inflight.size;
}
    public int num_stanzas_synced() {
       return this.stanzas_synced;
    }

    public static void start(StreamInteractor stream_interactor, Database db) {
        MamManager m = new MamManager(stream_interactor, db);
        stream_interactor.add_module(m);
            warning("MAM MANAGER START");
    }

private void on_account_added(Account account) {
        stream_interactor.module_manager.get_module(account, Xmpp.MessageModule.IDENTITY).received_message_unprocessed.connect((stream, message) => {
          string? id = message.stanza.get_deep_attribute("urn:xmpp:mam:2:result", "id");
          string? queryid = message.stanza.get_deep_attribute("urn:xmpp:mam:2:result", "queryid");
          StanzaNode? delay_node = message.stanza.get_deep_subnode("urn:xmpp:mam:2:result", "urn:xmpp:forward:0:forwarded", "urn:xmpp:delay:delay");
          if (id == null || queryid == null || delay_node == null) {
             if (id != null) {
             warning("[MAMv2] malformed MAM stanza: " + message.stanza.to_string());
             }
             return;
          }
            DateTime? time = DelayedDelivery.get_time_for_node(delay_node);
          if (time == null) return;
            DateTime? curtime = mam_times[queryid];
          if (curtime == null) {
            warning("[MAMv2 wtf] !!!! what happened to mam times for %s !!!!", queryid);
            return;
           }
           stanzas_synced += 1;
            mam_counts[queryid] += 1;
          if (time.compare(curtime) < 0) {
             mam_times[queryid] = time;
          debug("[MAMv2 query " + queryid + "] got stanza " + id + " at time " + time.to_string());
          }
       });
}
private async Iq.Stanza? query_archive(XmppStream stream, string query_id, string? target_jid, string? with, DateTime? start_time, DateTime? end_time, string? before) {
       var mam_module = stream.get_module(Xep.MessageArchiveManagement.Module.IDENTITY);
       var query_node = mam_module.crate_base_query(stream, with, query_id, start_time, end_time);
       query_node.put_node(mam_module.create_set_rsm_node(before));
       Iq.Stanza iq = new Iq.Stanza.set(query_node);
       if (target_jid != null) {
          iq.to = new Xmpp.Jid(target_jid);
       }
       return yield stream.get_module(Iq.Module.IDENTITY).send_iq_async(stream, iq);
}
public void notify_done(string jid, string body) {
Notification notification = new Notification("MAM done for " + jid);
notification.set_body(body);
GLib.Application.get_default().send_notification(jid + "-mam", notification);
}
public async void do_mam(Account account, string jid) {
            string query_id = Xmpp.random_uuid();
       if (mam_inflight.has_key(jid)) {
          warning("[MAMv2] SKIP DUPLICATE MAM QUERY FOR %s", jid);
          return;
       }
       mam_inflight[jid] = query_id;
       debug("[MAMv2 %s] doing query %s for %s", account.bare_jid.to_string(), query_id, jid);
       DateTime? start_time = null;
       long? prev_time = db.better_mam.select()
                    .with(db.better_mam.account_id, "=", account.id)
                    .with(db.better_mam.archive_jid, "=", jid) 
                    .single()
                    .get(db.better_mam.time);
       if (prev_time != null && prev_time != 0) {
          start_time = new DateTime.from_unix_utc(prev_time);
          debug("[MAMv2 %s] %s previously synced at %s", account.bare_jid.to_string(), jid, start_time.to_string());
       }

       XmppStream stream = stream_interactor.get_stream(account);
       mam_times[query_id] = new DateTime.now_utc();
       mam_counts[query_id] = 0;
       mam_start(account, jid, query_id);
       Iq.Stanza? iq = yield query_archive(stream, query_id, jid, null, start_time, null, null);
       if (iq == null) {
           warning("[MAMv2 query %s] hammed IQ :(", query_id);
           mam_inflight.unset(query_id);
       mam_stop(account, jid, query_id);
           return;
       }
        int queries = 0;
       while (iq != null) {
             string? complete = iq.stanza.get_deep_attribute("urn:xmpp:mam:2:fin", "complete");
             queries += 1;
             if (complete == "true") {

                debug("[MAMv2 query %s] done!", query_id);
                if (prev_time == 0) {
                notify_done(jid, queries.to_string() + " pages; " + mam_times[query_id].to_string());
                }
                DateTime now = new DateTime.now_utc();
                db.better_mam.upsert()
                  .value(db.better_mam.account_id, account.id, true)
                  .value(db.better_mam.archive_jid, jid, true)
                  .value(db.better_mam.time, (long) now.to_unix())
                  .perform();
                mam_inflight.unset(query_id);
       mam_stop(account, jid, query_id);
                return;
             }
             string? earliest_id = iq.stanza.get_deep_string_content("urn:xmpp:mam:2:fin", "http://jabber.org/protocol/rsm" + ":set", "first");
             if (earliest_id == null) {
                warning("[MAMv2 query %s] no earliest id :(", query_id);
                warning("[MAMv2] malformed MAM stanza: " + iq.stanza.to_string());
                mam_inflight.unset(query_id);
       mam_stop(account, jid, query_id);
                return;
             }
             string? count = iq.stanza.get_deep_string_content("urn:xmpp:mam:2:fin", "http://jabber.org/protocol/rsm" + ":set", "count");
             // give dino a breather, proportional to the number of inflight queries
                int wait_ms = 5 * num_inflight();
                Timeout.add(wait_ms, () => { Idle.add(do_mam.callback); return false; });
                yield;
             if (count != null) {
                long total = long.parse(count);
                long done = mam_counts[query_id];
                debug("[MAMv2 query %s] paging backward before %s; %lu/%lu done (%.2f)", query_id, earliest_id, done, total, done / total);
             }
             else {
             debug("[MAMv2 query %s] paging backward before %s", query_id, earliest_id);
             }
             // MAM go brrrrrrrrrrrrrrrrrrrrrr
             iq = yield query_archive(stream, query_id, jid, null, start_time, null, earliest_id);
       }
}

} // public class MamManager

} // namespace Dino


