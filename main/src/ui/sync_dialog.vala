using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Ui {

	public class SyncDialog : Gtk.Dialog {

		private Box box;
		private Box superbox;
		private Spinner spinner;
		private Label label;
		private ListBox syncing;
		private ScrolledWindow sw;
		private Button stop_button;
		private HashMap<string, Label> stati = new HashMap<string, Label>();
		private HashMap<string, string> query_ids = new HashMap<string, string>();
		private HashMap<Label, string> stati_reverse = new HashMap<Label, string>();
		private StreamInteractor stream_interactor;

		public SyncDialog(StreamInteractor stream_interactor) {
			Object(use_header_bar : Util.use_csd() ? 1 : 0);
			this.width_request = 400;
			this.deletable = false;
			this.height_request = 400;
			this.title = _("Archive Synchronization");
			this.stream_interactor = stream_interactor;
			this.superbox = new Box(Orientation.VERTICAL, 5);
			this.box = new Box(Orientation.HORIZONTAL, 5);
			this.superbox.margin = 10;
			this.spinner = new Spinner();
			this.spinner.margin_top = 10;
			this.spinner.margin_bottom = 10;
			this.stop_button = new Button.with_label("Skip syncing this chat");
			this.stop_button.sensitive = false;
			this.stop_button.visible = false;
			this.label = new Label("Please wait");
			this.label.margin_top = 10;
			this.label.margin_bottom = 10;
			this.sw = new ScrolledWindow(null, null);
			this.syncing = new ListBox();
			this.syncing.selection_mode = SelectionMode.SINGLE;
			this.box.pack_start(this.spinner, true, true);
			this.box.pack_start(this.label, true, true);
			this.superbox.pack_start(this.box, false, false);
			Label description = new Label("blah");
			description.set_markup("Downloading messages you missed...\nThis might take a while.\n<small>Click a chat to skip.</small>");
			description.margin_top = 5;
			description.margin_bottom = 5;
			this.superbox.pack_start(description, false, false);
			this.sw.max_content_height = 600;
			this.sw.min_content_height = 100;
			this.sw.add(this.syncing);
			this.sw.vexpand = true;
			this.superbox.pack_start(this.sw, true, true);
			this.superbox.pack_start(this.stop_button, false, false);
			get_content_area().add(this.superbox);

			this.syncing.row_selected.connect((row) => {
					stop_button.set_sensitive(row != null);
					stop_button.set_visible(row != null);
				});
			this.stop_button.clicked.connect(() => {
					ListBoxRow lbr = this.syncing.get_selected_row();
					Label status = lbr.get_child() as Label;
					stream_interactor.get_module(MamManager.IDENTITY).do_mam_cancel(stati_reverse[status]);
				});
		}

		public void set_remaining(int remaining) {
			label.set_markup("<span size=\"large\">Catching up on <b>" + remaining.to_string() + "</b> chats</span>");
		}

		public void update_query_id(string query_id, DateTime? time) {
			string jid = query_ids[query_id];
			Label status = stati[query_id];
			if (time != null) {
				string text = time.format("%T · %F");
				status.set_markup(jid + "\n<small><i>→ " + text + "</i></small>");
			}
			else {
				status.set_markup("<span foreground=\"gray\" size=\"small\">" + jid + "</span>");
			}
		}

		public void on_mam_start(Account account, string jid, string query_id) {
			int inflight = stream_interactor.get_module(MamManager.IDENTITY).num_inflight();
			set_remaining(inflight);
			query_ids[query_id] = jid;
			Label status = new Label("Syncing...");
			status.xalign = (float) 0.0;
			stati[query_id] = status;
			stati_reverse[status] = query_id;
			update_query_id(query_id, null);
			syncing.add(status);
			status.show_all();
		}

		public void on_mam_stop(Account account, string jid, string query_id) {
			int inflight = stream_interactor.get_module(MamManager.IDENTITY).num_inflight();
			set_remaining(inflight);
			if (inflight == 0) {
				spinner.stop();
				hide();
			}
			Label status = stati[query_id];
			status.hide();
			syncing.@foreach((widget) => {
					ListBoxRow? lbr = widget as ListBoxRow;
					if (lbr != null && lbr.get_child() == status) {
						syncing.remove(lbr);
					}
				});
			stati.unset(query_id);
			stati_reverse.unset(status);
		}

		public void on_mam_time(Account account, string query_id, DateTime time) {
			update_query_id(query_id, time);
			if (!visible) {
				show_all();
				stop_button.set_visible(stop_button.sensitive);
				spinner.start();
				present();
			}
		}
	}
}