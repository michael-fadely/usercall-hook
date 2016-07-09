import std.algorithm;
import std.array;
import std.exception;
import std.getopt;
import std.stdio;
import std.string;

// TODO: consolidate add esp
// TODO: float stuff

// TODO: actually this
bool isD = false;

void main(string[] argv)
{
	try
	{
		auto help = getopt(argv, "d|use-d", "Generate D inline assembly instead of MSVC++.", &isD);

		if (help.helpWanted || argv.length < 2)
		{
			defaultGetoptPrinter("usercall-hook [options] \"void __usercall function(a1@<ebx>)\" ...", help.options);
			return;
		}
	}
	catch (Exception ex)
	{
		stderr.writeln(ex.msg);
		return;
	}

	foreach (string s; argv[1 .. $])
	{
		try
		{
			parseDecl(s);
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.msg);
		}
	}
}

void parseDecl(in string str)
{
	auto decl = str.strip().idup;

	auto returnType = decl.munch("^ ");
	decl.munch(" ");

	while (returnType == "signed" || returnType == "unsigned")
	{
		returnType = decl.munch("^ ");
		decl.munch("* ");
	}

	auto convention = decl.munch("^ ");
	decl.munch(" ");

	bool purge = convention.endsWith("userpurge");
	enforce(convention.endsWith("usercall") || purge, "Provided declaration is neither usercall nor userpurge.");

	auto functionName = decl.munch("^@<(");
	decl.munch(" ");

	string returnRegister;
	if (returnType != "void")
	{
		decl.munch("@<");
		returnRegister = decl.munch("^>");
		decl.munch(">");
	}

	decl.munch("(");

	auto arguments = decl.munch("^);").split(',')
		.map!(x => x.strip())
		.array;

	size_t indent;

	void doIndent(size_t level = indent)
	{
		if (!level)
			return;

		stdout.write("\t".replicate(level));
	}

	stdout.writefln("static void __declspec(naked) %s()", functionName);
	stdout.writeln("{");
	++indent;

	doIndent(); stdout.writeln("__asm");
	doIndent(); stdout.writeln("{"); ++indent;

	string[2][] registers;
	size_t stack, stack_args;

	foreach_reverse (arg; arguments)
	{
		doIndent();

		auto _arg = arg.idup;
		_arg.munch("^ ");
		_arg.munch("* ");

		auto name = _arg.munch("^@<");
		_arg.munch("@<");

		auto register = _arg.munch("^>");
		_arg.munch(">");

		if (register.empty)
		{
			registers ~= [ null, name.idup ];
			stdout.writefln("push [esp + %02Xh] // %s", (4 * ++stack_args) + stack, name);
		}
		else
		{
			registers ~= [ register.idup, name.idup ];
			stdout.writefln("push %s // %s", register, name);
		}

		stack += 4;
	}

	stdout.writeln();

	doIndent();
	stdout.writeln("// Call your __cdecl function here:");

	doIndent();
	stdout.writeln("call func");

	stdout.writeln();

	foreach_reverse (register; registers)
	{
		doIndent();

		if (register[0] is null)
		{
			stdout.writeln("add esp, 4 // ", register[1]);
			continue;
		}

		if (register[0] == returnRegister)
		{
			stdout.writefln("add esp, 4 // %s<%s> is also used for return value", register[1], register[0]);
			continue;
		}

		stdout.writefln("pop %s // %s", register[0], register[1]);
	}

	doIndent();
	if (purge)
	{
		stdout.writefln("retn %02Xh", stack_args * 4);
	}
	else
	{
		stdout.writeln("retn");
	}

	for (; indent > 0; --indent)
	{
		doIndent(indent - 1);
		stdout.writeln("}");
	}

	stdout.writeln();
}
