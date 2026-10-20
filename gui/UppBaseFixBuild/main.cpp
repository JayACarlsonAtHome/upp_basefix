// UppBaseFixBuild: a window over upp_basefix.sh. Choose the compilers, debug or release,
// the tree (patched or pristine), strict warnings, a clean build, and the checks
// (ASan + UBSan, TSan, valgrind, helgrind); Start runs the script once per step, each
// as a child process in its own session (so Stop ends the compilers too), streams its
// output, and lists every "result:" line it prints. The tree buttons run pristine,
// patch, verify and status the same way. Double-click a result to read its log.
//
// Choices are kept in ~/.config/upp_basefix/build (key=value).
#include <CtrlLib/CtrlLib.h>

#include <signal.h>

using namespace Upp;

// upp_basefix.sh: $UPP_BASEFIX_HOME (set by "upp_basefix.sh gui"), else a folder above
// this program, else the usual clone.
static String ScriptPath()
{
	Vector<String> dirs;
	if(const char *h = getenv("UPP_BASEFIX_HOME"))
		dirs << h;
	for(String d = GetExeFolder(); d.GetCount() > 1; d = GetFileFolder(d))
		dirs << d;
	dirs << "/run/media/jay/GFS/git/upp_basefix";
	for(const String& d : dirs) {
		String s = AppendFileName(d, "upp_basefix.sh");
		if(FileExists(s))
			return s;
	}
	return String();
}

static String ShellQuote(const String& s)
{
	String q = "'";
	for(char c : s)
		q << (c == '\'' ? String("'\\''") : String(c, 1));
	return q + "'";
}

// 754 -> "00:12:34"
static String HmsClock(int64 secs)
{
	return Format("%02d:%02d:%02d", (int)(secs / 3600), (int)(secs / 60 % 60), (int)(secs % 60));
}

static String SettingsPath()
{
	return GetHomeDirFile(".config/upp_basefix/build");
}

namespace {

struct Step : Moveable<Step> {
	String         title;
	Vector<String> args;          // for upp_basefix.sh
	int64          started = 0, stopped = 0;
	int            code = -1;     // exit code; -1 not run yet
	String         summary;       // its "summary:" / "verify:" / last "status:" line
};

class BuildWindow : public TopWindow {
	enum { POLL = 1 };

	Splitter   top_split;
	ParentCtrl build_pane, checks_pane;
	LabelBox  options_box, checks_box;
	Label     compiler_label, type_label, tree_label;
	Switch    compiler, type, tree;
	Option    strict, clean, verbose, tests, asan, tsan, valgrind, helgrind;
	Label     tree_status;
	Button    pristine_b, patch_b, verify_b, status_b;
	Label     command;

	Splitter  split;
	ArrayCtrl steps_list, results_list;
	LineEdit  output;

	Label     running;
	Button    start, stop, close;

	String       script;
	Vector<Step> steps;
	int          step = -1;
	One<LocalProcess> proc;
	bool         stopping = false;
	int64        all_started = 0;
	String       partial;

	void Plan();
	void ShowCommand();
	void Load();
	void Save();
	void RunPlan();
	void RunOne(const String& title, const Vector<String>& args);
	void NextStep();
	void Poll();
	void Out(const String& text);
	void Line(const String& line);
	void StepDone();
	void Finish();
	void Stop();
	void TreeStatus();
	void ShowLog();
	void Busy(bool b);

public:
	void Close() override;
	BuildWindow();
	~BuildWindow();
};

}

BuildWindow::BuildWindow()
{
	script = ScriptPath();
	Title("UppBaseFixBuild - U++ 18619 + patches");
	Sizeable().Zoomable();
	SetRect(0, 0, Zx(1100), Zy(820));

	// Build options (left) and checks (right), side by side
	build_pane.Add(options_box.SetLabel("Build").SizePos());
	build_pane.Add(compiler_label.SetText("Compiler:").LeftPosZ(12, 70).TopPosZ(20, 22));
	compiler.Add("gcc", "gcc 15").Add("clang", "clang").Add("both", "both");
	compiler.Tip("both: gcc, then clang");
	build_pane.Add(compiler.HSizePosZ(84, 8).TopPosZ(20, 22));
	build_pane.Add(type_label.SetText("Type:").LeftPosZ(12, 70).TopPosZ(44, 22));
	type.Add("debug", "Debug").Add("release", "Release (optimized)");
	build_pane.Add(type.HSizePosZ(84, 8).TopPosZ(44, 22));
	build_pane.Add(tree_label.SetText("Tree:").LeftPosZ(12, 70).TopPosZ(68, 22));
	tree.Add("patched", "Patched (18619 + patches)").Add("pristine", "Pristine (18619)");
	build_pane.Add(tree.HSizePosZ(84, 8).TopPosZ(68, 22));
	strict.SetLabel("Strict (-Wall -Wextra)");
	strict.Tip("U++ house style (unused parameters, deprecated copies, && within ||, and the sites in "
	           "supp/strict-reviewed.txt) is counted apart; any other U++ warning turns the row yellow");
	build_pane.Add(strict.LeftPosZ(12, 230).TopPosZ(92, 22));
	clean.SetLabel("Clean build (all files)");
	clean.Tip("Compile everything: the warning counts then cover the whole tree");
	build_pane.Add(clean.LeftPosZ(250, 230).TopPosZ(92, 22));
	verbose.SetLabel("Show every file compiled");
	build_pane.Add(verbose.LeftPosZ(12, 230).TopPosZ(116, 22));

	checks_pane.Add(checks_box.SetLabel("Checks").SizePos());
	tests.SetLabel("Run the check programs after building");
	tests.Tip("UppBaseCheck: the console checks; UppBaseCheckGui --smoke");
	checks_pane.Add(tests.HSizePosZ(12, 8).TopPosZ(20, 22));
	asan.SetLabel("AddressSanitizer + UBSan (each compiler)");
	asan.Tip("Memory errors, leaks, undefined behaviour");
	checks_pane.Add(asan.HSizePosZ(32, 8).TopPosZ(44, 22));
	tsan.SetLabel("ThreadSanitizer (clang)");
	tsan.Tip("Data races between threads");
	checks_pane.Add(tsan.HSizePosZ(32, 8).TopPosZ(68, 22));
	valgrind.SetLabel("valgrind memcheck (each compiler; slow)");
	valgrind.Tip("Uninitialised reads, leaks");
	checks_pane.Add(valgrind.HSizePosZ(32, 8).TopPosZ(92, 22));
	helgrind.SetLabel("valgrind helgrind (once; very slow)");
	helgrind.Tip("Races, lock order; gcc when both; the GUI program is not run under it");
	checks_pane.Add(helgrind.HSizePosZ(32, 8).TopPosZ(116, 22));

	top_split.Horz(build_pane, checks_pane);
	Add(top_split.HSizePosZ(8, 8).TopPosZ(4, 146));

	// Text above, every button on the bottom row: Start, Stop, the trees ... Close
	Add(tree_status.SetAlign(ALIGN_RIGHT).RightPosZ(8, 540).BottomPosZ(40, 22));
	Add(pristine_b.SetLabel("Copy pristine").RightPosZ(478, 120).BottomPosZ(8, 28));
	Add(patch_b.SetLabel("Apply patches").RightPosZ(352, 120).BottomPosZ(8, 28));
	Add(verify_b.SetLabel("Verify pin").RightPosZ(226, 120).BottomPosZ(8, 28));
	Add(status_b.SetLabel("Patch status").RightPosZ(104, 116).BottomPosZ(8, 28));
	pristine_b.Tip("upp_basefix.sh pristine: copies /run/media/jay/GFS/upp/uppsrc (originals put back) "
	               "and checks it against the pin");
	patch_b.Tip("upp_basefix.sh patch: pristine + patches/*.patch -> the patched tree");
	verify_b.Tip("upp_basefix.sh verify: the pristine tree against pin/uppsrc-18619.sha256 (3031 files)");
	status_b.Tip("upp_basefix.sh status: which patches the patched tree has");

	command.SetFont(Monospace());
	Add(command.HSizePosZ(8, 8).TopPosZ(154, 80));

	// Steps, results, output
	steps_list.AddColumn("Step", 50);
	steps_list.AddColumn("State", 10);
	steps_list.AddColumn("Time", 8).SetDisplay(StdRightDisplay()).HeaderTab().AlignRight();
	steps_list.AddColumn("Summary", 32);
	steps_list.NoCursor();
	results_list.AddColumn("Result", 40);
	results_list.AddColumn("State", 12);
	results_list.AddColumn("Time", 7).SetDisplay(StdRightDisplay()).HeaderTab().AlignRight();
	results_list.AddColumn("Warnings / checks", 41);
	results_list.AddIndex("log");
	results_list.WhenLeftDouble = [this] { ShowLog(); };
	results_list.Tip("Double-click a build result to see its whole log below");
	output.SetReadOnly();
	output.SetFont(Monospace());
	split.Vert() << steps_list << results_list << output;
	split.SetPos(1800, 0).SetPos(4300, 1);
	Add(split.HSizePosZ(8, 8).VSizePosZ(238, 66));

	Add(start.SetLabel("Start").LeftPosZ(8, 110).BottomPosZ(8, 28));
	Add(stop.SetLabel("Stop").LeftPosZ(124, 110).BottomPosZ(8, 28));
	Add(close.SetLabel("Close").RightPosZ(8, 90).BottomPosZ(8, 28));
	Add(running.HSizePosZ(8, 556).BottomPosZ(40, 22));

	for(Ctrl *c : { (Ctrl *)&compiler, (Ctrl *)&type, (Ctrl *)&tree, (Ctrl *)&strict, (Ctrl *)&clean,
	                (Ctrl *)&verbose, (Ctrl *)&tests, (Ctrl *)&asan, (Ctrl *)&tsan, (Ctrl *)&valgrind,
	                (Ctrl *)&helgrind })
		*c << [this] { ShowCommand(); };
	start << [this] { Save(); RunPlan(); };
	stop << [this] { Stop(); };
	close << [this] { Close(); };
	pristine_b << [this] { RunOne("copy the pristine tree, check it against the pin", { "pristine" }); };
	patch_b << [this] { RunOne("apply the patches -> patched tree", { "patch" }); };
	verify_b << [this] { RunOne("verify the pristine tree against the pin", { "verify" }); };
	status_b << [this] { RunOne("which patches the patched tree has", { "status" }); };

	Load();
	ShowCommand();
	TreeStatus();
	Busy(false);
	if(script.IsEmpty()) {
		start.Disable();
		command = "upp_basefix.sh not found: set UPP_BASEFIX_HOME, or start this with ./upp_basefix.sh gui";
	}
	running = script.GetCount() ? "Ready.  Script: " + script : String();
}

BuildWindow::~BuildWindow()
{
	KillTimeCallback(POLL);
	if(proc && proc->IsRunning())
		kill(-proc->GetPid(), SIGTERM);
}

// One build (or test) run with the chosen compilers, then one per ticked check.
// ThreadSanitizer runs with clang, helgrind once (gcc unless clang alone was chosen).
void BuildWindow::Plan()
{
	steps.Clear();
	String c = ~compiler;
	bool release = String(~type) == "release";
	auto common = [&](Vector<String>& a, const String& cc) {
		a << "--compiler" << cc << "--tree" << AsString(~tree);
		if(release)
			a << "--release";
		if(strict)
			a << "--strict";
		if(verbose)
			a << "--verbose";
	};
	String what = String(release ? "release" : "debug") + (strict ? ", strict" : "") + ", " + AsString(~tree);
	Step& s = steps.Add();
	s.args << (tests ? "test" : "build");
	common(s.args, c);
	if(clean)
		s.args << "--clean";
	s.title = (c == "both" ? String("gcc + clang") : c) + " " + what + (clean ? ", clean" : "") +
	          (tests ? ": build + checks" : ": build");
	if(!tests)
		return;
	auto check = [&](const String& cc, const char *flag, const char *name) {
		Step& s = steps.Add();
		s.args << "test";
		common(s.args, cc);
		s.args << String("--") + flag;
		s.title = (cc == "both" ? String("gcc + clang") : cc) + " " + what + ": under " + name;
	};
	if(asan)
		check(c, "asan", "ASan + UBSan");
	if(tsan)
		check("clang", "tsan", "ThreadSanitizer");
	if(valgrind)
		check(c, "valgrind", "valgrind memcheck");
	if(helgrind)
		check(c == "clang" ? "clang" : "gcc", "helgrind", "valgrind helgrind");
}

void BuildWindow::ShowCommand()
{
	Plan();
	String text;
	for(const Step& s : steps)
		text << (text.GetCount() ? "\n" : "") << "./upp_basefix.sh " << Join(s.args, " ");
	command = text;
	for(Option *o : { &asan, &tsan, &valgrind, &helgrind })
		o->Enable(tests);
}

void BuildWindow::Load()
{
	compiler <<= "both";
	type <<= "debug";
	tree <<= "patched";
	verbose = true;
	tests = true;
	for(String line : Split(LoadFile(SettingsPath()), '\n')) {
		int q = line.Find('=');
		if(q < 0)
			continue;
		String key = line.Left(q), value = line.Mid(q + 1);
		if(key == "compiler" && (value == "gcc" || value == "clang" || value == "both"))
			compiler <<= value;
		else if(key == "type" && (value == "debug" || value == "release"))
			type <<= value;
		else if(key == "tree" && (value == "patched" || value == "pristine"))
			tree <<= value;
		for(auto [name, o] : { std::pair<const char *, Option *>{ "strict", &strict }, { "clean", &clean },
		                       { "verbose", &verbose }, { "tests", &tests }, { "asan", &asan },
		                       { "tsan", &tsan }, { "valgrind", &valgrind }, { "helgrind", &helgrind } })
			if(key == name)
				*o = value == "1";
	}
}

void BuildWindow::Save()
{
	String text = "compiler=" + AsString(~compiler) + "\ntype=" + AsString(~type) + "\ntree=" + AsString(~tree) + "\n";
	for(auto [name, o] : { std::pair<const char *, Option *>{ "strict", &strict }, { "clean", &clean },
	                       { "verbose", &verbose }, { "tests", &tests }, { "asan", &asan },
	                       { "tsan", &tsan }, { "valgrind", &valgrind }, { "helgrind", &helgrind } })
		text << name << "=" << (int)o->Get() << "\n";
	RealizePath(SettingsPath());
	SaveFile(SettingsPath(), text);
}

// Which trees the work folder has, and whether the patched one has every patch (fast).
void BuildWindow::TreeStatus()
{
	if(script.IsEmpty())
		return;
	String out;
	bool ok = Sys("bash " + ShellQuote(script) + " status", out) == 0;
	String last;
	for(const String& line : Split(out, '\n'))
		if(line.StartsWith("status: ") && line.Find(" of ") > 0)
			last = line.Mid(8);
	if(last.IsEmpty())
		last = "no patched tree yet: Copy pristine, then Apply patches";
	tree_status = "Patched tree: " + last;
	tree_status.SetInk(ok ? Color(0, 128, 0) : LtRed());
}

void BuildWindow::Busy(bool b)
{
	start.Enable(!b && script.GetCount());
	stop.Enable(b);
	for(Button *x : { &pristine_b, &patch_b, &verify_b, &status_b })
		x->Enable(!b && script.GetCount());
}

void BuildWindow::RunPlan()
{
	Plan();
	steps_list.Clear();
	results_list.Clear();
	for(const Step& s : steps)
		steps_list.Add(s.title, "waiting", "", "");
	output.Clear();
	stopping = false;
	all_started = (int64)time(nullptr);
	step = -1;
	Busy(true);
	NextStep();
}

// A tree button: one step on its own.
void BuildWindow::RunOne(const String& title, const Vector<String>& args)
{
	steps.Clear();
	Step& s = steps.Add();
	s.title = title;
	s.args = clone(args);
	steps_list.Clear();
	results_list.Clear();
	steps_list.Add(s.title, "waiting", "", "");
	output.Clear();
	stopping = false;
	all_started = (int64)time(nullptr);
	step = -1;
	Busy(true);
	NextStep();
}

void BuildWindow::NextStep()
{
	if(++step >= steps.GetCount() || stopping) {
		Finish();
		return;
	}
	Step& s = steps[step];
	Vector<String> args;
	args << "bash" << script;
	args.Append(s.args);
	Out("\n== " + s.title + "\n$ ./upp_basefix.sh " + Join(s.args, " ") + "\n");
	s.started = (int64)time(nullptr);
	steps_list.Set(step, 1, "running");
	partial.Clear();
	proc.Create();
	if(!proc->Start("/usr/bin/setsid", args, nullptr, GetFileFolder(script))) {
		Out("cannot start upp_basefix.sh\n");
		s.code = 127;
		StepDone();
		return;
	}
	SetTimeCallback(-100, [this] { Poll(); }, POLL);
}

void BuildWindow::Poll()
{
	if(!proc)
		return;
	String s;
	while(proc->Read(s) && s.GetCount()) {
		Out(s);
		s.Clear();
	}
	if(step >= 0 && step < steps.GetCount()) {
		int64 now = (int64)time(nullptr);
		steps_list.Set(step, 2, HmsClock(now - steps[step].started));
	}
	if(!proc->IsRunning()) {
		KillTimeCallback(POLL);
		while(proc->Read(s) && s.GetCount()) {
			Out(s);
			s.Clear();
		}
		steps[step].code = proc->GetExitCode();
		proc.Clear();
		StepDone();
	}
}

void BuildWindow::Out(const String& text)
{
	partial << text;
	int nl = partial.ReverseFind('\n');
	if(nl >= 0) {
		for(const String& line : Split(partial.Left(nl), '\n', false))
			Line(line);
		partial = partial.Mid(nl + 1);
	}
	output.Insert(output.GetLength(), text.ToWString());
	if(output.GetLineCount() > 20000)
		output.Remove(0, output.GetPos(output.GetLineCount() - 15000));
	output.SetCursor(output.GetLength());
}

// The script's own lines: "step:" says what it is doing, "result:" is one finished
// build or run, "summary:" / "verify:" / "status: N of M" sum the step up.
void BuildWindow::Line(const String& line)
{
	if(step < 0 || step >= steps.GetCount())
		return;
	if(line.StartsWith("step: "))
		running = Format("Step %d of %d: %s", step + 1, steps.GetCount(), line.Mid(6));
	else if(line.StartsWith("summary: ") || line.StartsWith("verify: ") ||
	        (line.StartsWith("status: ") && line.Find(" of ") > 0))
		steps[step].summary = TrimBoth(line.Mid(line.Find(':') + 1));
	else if(line.StartsWith("error: "))
		steps[step].summary = TrimBoth(line);
	else if(line.StartsWith("result: ")) {
		// result: build UppBaseCheck gcc debug: ok 12 s  warnings: ours 0, U++ 0 (unique)  log: ...
		// result: test UppBaseCheck clang debug asan: FAILED (exit 1)  passed: 11/11 checks
		String r = line.Mid(8);
		int q = r.Find(": ");
		String what = q >= 0 ? r.Left(q) : r, rest = q >= 0 ? r.Mid(q + 2) : String();
		String log;
		int l = rest.Find("  log: ");
		if(l >= 0) {
			log = TrimBoth(rest.Mid(l + 7));
			rest = rest.Left(l);
		}
		String state = rest.StartsWith("ok") ? "ok" : rest.StartsWith("skipped") ? "skipped" : "FAILED";
		String secs, detail;
		Vector<String> w = Split(rest, ' ');
		for(int i = 1; i < w.GetCount(); i++)
			if(w[i] == "s" && IsDigit(*w[i - 1]))
				secs = w[i - 1] + " s";
		int d = rest.Find("warnings: ");
		if(d < 0)
			d = rest.Find("passed: ");
		if(d >= 0)
			detail = TrimBoth(rest.Mid(d));
		else if(state != "ok")
			detail = TrimBoth(rest);
		if(state == "FAILED" && rest.Find("(exit") >= 0)
			state = TrimBoth(rest.Left(rest.Find(")") + 1));
		results_list.Add(what, state, secs, detail, log);
		int row = results_list.GetCount() - 1;
		bool warned = detail.StartsWith("warnings: ") && !detail.StartsWith("warnings: ours 0, U++ 0 (") &&
		              !detail.StartsWith("warnings: ours 0, U++ 0, ");
		if(state.StartsWith("FAILED"))
			results_list.SetLineColor(row, Color(255, 215, 215));
		else if(warned)
			results_list.SetLineColor(row, Color(255, 240, 190));
		results_list.ScrollEnd();
	}
}

void BuildWindow::StepDone()
{
	Step& s = steps[step];
	s.stopped = (int64)time(nullptr);
	steps_list.Set(step, 1, stopping ? "stopped" : s.code == 0 ? "good" : "FAILED");
	steps_list.Set(step, 2, HmsClock(s.stopped - s.started));
	steps_list.Set(step, 3, s.summary);
	if(s.code != 0)
		steps_list.SetLineColor(step, Color(255, 215, 215));
	NextStep();
}

void BuildWindow::Finish()
{
	Busy(false);
	bool good = !stopping;
	int fails = 0;
	for(const Step& s : steps)
		if(s.code > 0 || (s.code < 0 && !stopping))
			fails++;
	good = good && fails == 0;
	running = (good ? "Done: all good" : stopping ? "Stopped" : Format("Done: %d step(s) FAILED (red)", fails)) +
	          String("  -  ") + TrimBoth(HmsClock((int64)time(nullptr) - all_started)) + " in all";
	running.SetInk(good ? Color(0, 128, 0) : LtRed());
	TreeStatus();
}

void BuildWindow::ShowLog()
{
	int row = results_list.GetCursor();
	if(row < 0)
		return;
	String log = results_list.Get(row, "log");
	if(log.IsEmpty() || !FileExists(log)) {
		PromptOK("This result has no log file (the check programs' output is in the pane below).");
		return;
	}
	if(proc) {
		PromptOK("Wait for the run to finish (its output is in the pane below), then double-click again.");
		return;
	}
	output <<= "== " + log + "\n\n" + LoadFile(log);
	output.SetCursor(0);
}

void BuildWindow::Stop()
{
	stopping = true;
	if(proc && proc->IsRunning())
		kill(-proc->GetPid(), SIGTERM);
}

void BuildWindow::Close()
{
	if(proc && proc->IsRunning()) {
		if(!PromptYesNo("A run is going. Stop it and close?"))
			return;
		Stop();
		for(int i = 0; i < 50 && proc->IsRunning(); i++)
			Sleep(100);
	}
	TopWindow::Close();
}

GUI_APP_MAIN
{
	if(FindIndex(CommandLine(), String("--smoke")) >= 0) {   // opens, then closes
		BuildWindow w;
		w.Open();
		SetTimeCallback(500, [&] { w.Close(); });
		Ctrl::EventLoop(&w);
		Cout() << "smoke: ok\n";
		return;
	}
	BuildWindow().Execute();
}
