using Gee;

using Xmpp;
using Xmpp.Xep;
using Dino.Entities;
using Qlite;

namespace Dino {

public class MamManager : StreamInteractionModule, Object {
       public static ModuleIdentity<MamManager> IDENTITY = new ModuleIdentity<MamManager>("mam_manager");
       public string id { get { return IDENTITY.id; } }
    private StreamInteractor stream_interactor;
    private Database db;


    private MamManager(StreamInteractor stream_interactor, Database db) {
            this.stream_interactor = stream_interactor;
            this.db = db;
    }

    public static void start(StreamInteractor stream_interactor, Database db) {
        MamManager m = new MamManager(stream_interactor, db);
        stream_interactor.add_module(m);
    }


} // public class MamManager

} // namespace Dino


