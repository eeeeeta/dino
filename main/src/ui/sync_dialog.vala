using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;
using Xmpp.Xep;

namespace Dino.Ui {

public class SyncDialog : Gtk.Dialog {

       private Box box;
       private Spinner spinner;
       private Label label;
       private StreamInteractor stream_interactor;

       public SyncDialog(StreamInteractor stream_interactor) {
              Object(use_header_bar : Util.use_csd() ? 1 : 0);
              this.title = _("Synchronization in progress");
              this.stream_interactor = stream_interactor;
              this.box = new Box(Orientation.HORIZONTAL, 5);
              this.spinner = new Spinner();
              this.label = new Label("Please wait");
              this.box.pack_start(this.spinner);
              this.box.pack_start(this.label);
              get_content_area().add(this.box);
       }

       public void set_remaining(int remaining) {
              this.label.set_text(remaining.to_string() + " conversations synchronizing...");
             }
             }
             }