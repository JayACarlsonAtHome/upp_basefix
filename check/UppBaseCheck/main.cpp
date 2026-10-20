// UppBaseCheck: runs the U++ packages the projects use (Core, Core/SSH, Draw,
// plugin/png, plugin/sqlite3) once each, so a patched U++ is shown to build AND work.
// No display needed: fit for valgrind and the sanitizers. Prints one line per check,
// then "passed: N/M checks"; the exit code is the number of failures.
#include <Core/Core.h>
#include <Core/SSH/SSH.h>
#include <Draw/Draw.h>
#include <plugin/png/png.h>
#include <plugin/sqlite3/Sqlite3.h>
#include <RichText/RichText.h>

using namespace Upp;

static int checks, failed;

static void Expect(bool ok, const char *what)
{
	checks++;
	if(!ok)
		failed++;
	Cout() << (ok ? "ok   " : "FAIL ") << what << "\n";
}

static void CheckCore()
{
	String s = Format("%d %s %.2f", 42, "x", 1.5);
	Expect(s == "42 x 1.50", "Format");
	Vector<int> v;
	for(int i = 0; i < 1000; i++)
		v.Add((i * 7919) % 1000);
	Sort(v);
	bool sorted = true;
	for(int i = 1; i < v.GetCount(); i++)
		sorted = sorted && v[i - 1] <= v[i];
	Expect(sorted && v.GetCount() == 1000, "Vector + Sort");
	VectorMap<String, int> m;
	for(int i = 0; i < 100; i++)
		m.Add(AsString(i), i);
	Expect(m.Get("57", -1) == 57 && m.Find("100") < 0, "VectorMap");
	Expect(ToUpper(String("abc")) == "ABC" && TrimBoth("  a  ") == "a", "string utilities");
	Expect(SHA256String("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256");
}

// Many threads allocate and free at once: U++'s per-thread heap (patch 0001) under load.
static void CheckThreadsAndHeap()
{
	std::atomic<int64> sum = 0;
	CoWork co;
	for(int t = 0; t < 8; t++)
		co & [&sum, t] {
			int64 local = 0;
			for(int i = 0; i < 20000; i++) {
				String s = AsString(i + t);
				Vector<String> parts;
				parts.Add(s);
				parts.Add(s + s);
				local += parts[1].GetCount();
			}
			sum += local;
		};
	co.Finish();
	int64 want = 0;
	for(int t = 0; t < 8; t++)
		for(int i = 0; i < 20000; i++)
			want += 2 * AsString(i + t).GetCount();
	Expect(sum == want, "CoWork: 8 threads allocating at once");
}

static void CheckSqlite()
{
	Sqlite3Session db;
	bool open = db.Open(":memory:");
	Expect(open, "SQLite: open :memory:");
	if(!open)
		return;
	Sql q(db);
	bool ok = q.Execute("create table t(a integer, b text)") &&
	          q.Execute("insert into t values(1, 'one')") &&
	          q.Execute("insert into t values(2, 'two')") &&
	          q.Execute("select sum(a), group_concat(b, ',') from t") && q.Fetch();
	Expect(ok && (int)q[0] == 3 && (String)q[1] == "one,two", "SQLite: create, insert, select");
	Expect(q.Execute("select sqlite_version()") && q.Fetch() && ((String)q[0]).GetCount() > 0, "SQLite: version");
}

static void CheckPng()
{
	ImageBuffer ib(16, 8);
	for(int y = 0; y < 8; y++)
		for(int x = 0; x < 16; x++)
			ib[y][x] = Color(x * 16, y * 32, 128);
	Image img = ib;
	String png = PNGEncoder().SaveString(img);
	Image back = StreamRaster::LoadStringAny(png);
	bool same = back.GetSize() == img.GetSize();
	for(int y = 0; same && y < 8; y++)
		for(int x = 0; same && x < 16; x++)
			same = back[y][x] == img[y][x];
	Expect(png.GetCount() > 0 && same, "PNG: encode and read back");
}

// Bugs the patches fix, one check each: these fail on the pristine tree.
static void CheckPatchedBugs()
{
	auto decode = [](const char *text) -> int {   // first character of a C string literal
		try {
			WString w = CParser(text).ReadString().ToWString();
			return w.GetCount() ? (int)w[0] : -1;
		}
		catch(CParser::Error) {
			return -2;
		}
	};
	// 0009: \uD83D\uDE00 is U+1F600; \uD840\uDC00 is U+20000 (bit 16: the + / | slip);
	// \uDBFF\uDFFF is U+10FFFF (0xDBFF is a high surrogate too)
	Expect(decode("\"\\uD83D\\uDE00\"") == 0x1F600, "CParser: surrogate pair U+1F600");
	Expect(decode("\"\\uD840\\uDC00\"") == 0x20000, "CParser: surrogate pair U+20000");
	Expect(decode("\"\\uDBFF\\uDFFF\"") == 0x10FFFF, "CParser: surrogate pair U+10FFFF");
	// 0009: Equalight stretches a low-contrast image (it returned it unchanged)
	ImageBuffer ib(16, 16);
	for(int y = 0; y < 16; y++)
		for(int x = 0; x < 16; x++) {
			RGBA& c = ib[y][x];
			c.r = c.g = c.b = (byte)(100 + 2 * x + y % 2);
			c.a = 255;
		}
	Image flat = ib;
	Image eq = Equalight(flat, 10);
	Expect(eq[0][0].r < flat[0][0].r && eq[0][15].r > flat[0][15].r, "Equalight: stretches contrast");
	// 0009: memory status: sysconf's -1 is not taken as a huge unsigned count
	uint64 total = 0, avail = 0;
	GetSystemMemoryStatus(total, avail);
	Expect(total > 0 && avail <= total && total < ((uint64)1 << 50), "GetSystemMemoryStatus");
	// 0015: QTF that ends too soon: the parser stops at the NUL (it read on past it; the
	// bytes after the NUL here are ours, so the old reads are visible, not undefined)
	static const char cut_p[] = "[p\0XYZ";
	String e = ParseQTF(cut_p).GetPlainText().ToString();
	Expect(e.Find("Unexpected end of text") >= 0 && e.Find("XYZ") < 0, "QTF: end of text in a paragraph format");
	static const char cut_color[] = "[@\0 abc";
	Expect(ParseQTF(cut_color).GetPlainText().ToString().Find("abc") < 0, "QTF: end of text in a color");
	// 0016: findarg compares integers by value: -1 is not 0xFFFFFFFF
	Expect(findarg(0xFFFFFFFFu, -1) < 0 && findarg(3u, 1, 2, 3) == 2 && findarg('b', 'a', 'b') == 1, "findarg: signed and unsigned");
}

static void CheckSsh()
{
	SshSession ssh;   // no connection: the package links and its objects come and go
	ssh.Timeout(1000);
	Expect(!ssh.IsError(), "SSH: session object");
}

CONSOLE_APP_MAIN
{
	CheckCore();
	CheckThreadsAndHeap();
	CheckSqlite();
	CheckPng();
	CheckPatchedBugs();
	CheckSsh();
	Cout() << (failed ? "FAILED: " : "passed: ") << checks - failed << "/" << checks << " checks\n";
	SetExitCode(failed);
}
