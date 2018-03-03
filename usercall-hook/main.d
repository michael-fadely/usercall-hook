import std.algorithm;
import std.array;
import std.exception;
import std.getopt;
import std.stdio;
import std.string;

// TODO: consolidate "add esp, x"
// TODO: stack alignment (default should be 4; e.g don't push ax, push eax)
// TODO: float stuff

// TODO: actually do this
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
		.map!strip
		.array;

	size_t indent;

	void doIndent(size_t level = indent)
	{
		if (level)
		{
			stdout.write("\t".replicate(level));
		}
	}

	stdout.writefln("static void __declspec(naked) %s()", functionName);
	stdout.writeln("{");
	++indent;

	doIndent(); stdout.writeln("__asm");
	doIndent(); stdout.writeln("{"); ++indent;

	string[2][] parsedArgs;

	foreach_reverse (arg; arguments)
	{
		auto _arg = arg.idup;
		_arg.munch("^ ");
		_arg.munch("* ");

		auto name = _arg.munch("^@<");
		_arg.munch("@<");

		auto register = _arg.munch("^>");
		_arg.munch(">");

		parsedArgs ~= (register.empty) ? [ null, name.idup ] : [ register.idup, name.idup ];
	}

	// used later if this is userpurge
	size_t stackArgCount = parsedArgs.count!(x => x[0].empty);

	size_t _count = stackArgCount;
	size_t stack;

	foreach (arg; parsedArgs)
	{
		doIndent();

		if (arg[0].empty)
		{
			enforce(stackArgCount > 0, "Parse error");
			stdout.writefln("push [esp + %02Xh] // %s", (4 * _count--) + stack, arg[1]);
		}
		else
		{
			stdout.writefln("push %s // %s", arg[0], arg[1]);
		}

		stack += 4;
	}

	stdout.writeln();

	doIndent();
	stdout.writeln("// Call your __cdecl function here:");

	doIndent();
	stdout.writeln("call func");

	stdout.writeln();

	foreach_reverse (register; parsedArgs)
	{
		doIndent();

		if (register[0].empty)
		{
			stdout.writeln("add esp, 4 // ", register[1]);
			continue;
		}

		// TODO: variable size registers (e.g eax == ax == ah == al)
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
		// corrects the stack for the calling function
		stdout.writefln("retn %02Xh", 4 * stackArgCount);
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
