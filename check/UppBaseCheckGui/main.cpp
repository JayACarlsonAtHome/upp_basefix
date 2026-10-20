// UppBaseCheckGui: opens a CtrlLib window with a few common controls (so CtrlLib,
// CtrlCore, Draw and Painter are built and started), then closes it.
//   UppBaseCheckGui            stays open until closed
//   UppBaseCheckGui --smoke    closes itself after half a second, prints "smoke: ok"
#include <CtrlLib/CtrlLib.h>

using namespace Upp;

GUI_APP_MAIN
{
	bool smoke = FindIndex(CommandLine(), "--smoke") >= 0;
	TopWindow w;
	w.Title("upp_basefix check").SetRect(0, 0, 420, 220);
	Label label;
	EditField edit;
	Button ok;
	ArrayCtrl list;
	label.SetLabel("U++ with the upp_basefix patches");
	edit <<= "edit me";
	ok.SetLabel("Close");
	ok << [&] { w.Close(); };
	list.AddColumn("Package");
	list.AddColumn("State");
	for(const char *p : { "Core", "Draw", "Painter", "CtrlCore", "CtrlLib" })
		list.Add(p, "built");
	w.Add(label.TopPos(8, 20).HSizePos(8, 8));
	w.Add(edit.TopPos(32, 22).HSizePos(8, 8));
	w.Add(list.VSizePos(62, 40).HSizePos(8, 8));
	w.Add(ok.BottomPos(8, 24).RightPos(8, 80));
	if(smoke)
		SetTimeCallback(500, [&] { w.Close(); });
	w.Run();
	if(smoke)
		Cout() << "smoke: ok\n";
}
