import std.algorithm;
import std.array;
import std.exception;
import std.getopt;
import std.stdio;
import std.string;
import std.uni : isWhite;

// TODO: consolidate "add esp, x"
// TODO: stack alignment (default should be 4; e.g don't push ax, push eax)
// TODO: float stuff

void main(string[] argv)
{
	try
	{
		auto help = getopt(argv);

		if (help.helpWanted || argv.length < 2)
		{
			defaultGetoptPrinter(`usercall-hook "void __usercall function(a1@<ebx>)" ...`, help.options);
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

void parseDecl(string decl)
{
	auto returnType = decl.takeUntil!isWhite;
	decl.takeWhile!isWhite;

	while (returnType == "signed" || returnType == "unsigned")
	{
		returnType = decl.takeUntil!isWhite;
		decl.takeWhile!((x) => isWhite(x) || x == '*');
	}

	auto convention = decl.takeUntil!isWhite;
	decl.takeWhile!isWhite;

	bool purge = convention.endsWith("userpurge");
	enforce(convention.endsWith("usercall") || purge, "Provided declaration is neither usercall nor userpurge.");

	auto functionName = decl.takeUntilAny("@<(");
	decl.takeWhile!isWhite;

	string returnRegister;

	if (returnType != "void")
	{
		decl.takeWhileAny("@<");
		returnRegister = decl.takeUntil('>');
		decl.takeWhile('>');
	}

	decl.takeWhile('(');

	auto arguments = decl
		.takeUntilAny(");")
		.split(',')
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
		_arg.takeUntil!isWhite;
		_arg.takeWhile!((x) => isWhite(x) || x == '*');

		auto name = _arg.takeUntilAny("@<");
		_arg.takeWhileAny("@<");

		auto register = _arg.takeUntil('>');
		_arg.takeWhile('>');

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

// convenience functions

/**
	Returns a slice of `arr` from 0 until the index where `pred` is satisfied.
	`arr` is narrowed to the range after that point.

	Params:
		pred = Predicate.
		arr  = Array to search.

	Returns:
		Slice of `arr`.
 */
R[] takeUntil(alias pred, R)(ref R[] arr)
{
	foreach (size_t i, e; arr)
	{
		if (pred(e))
		{
			auto result = arr[0 .. i];
			arr = arr[(i > $ ? $ : i) .. $];
			return result;
		}
	}

	return arr;
}

/**
	Returns a slice of `arr` from 0 until the index where `element` is found.
	`arr` is narrowed to the range after that point.

	Params:
		arr     = Array to search.
		element = The element to search for.

	Returns:
		Slice of `arr`.
 */
R[] takeUntil(R)(ref R[] arr, in R element)
{
	foreach (size_t i, e; arr)
	{
		if (e == element)
		{
			auto result = arr[0 .. i];
			arr = arr[(i > $ ? $ : i) .. $];
			return result;
		}
	}

	return arr;
}

/**
	Returns a slice of `arr` from 0 until the index where any element of `a` is found.
	`arr` is narrowed to the range after that point.

	Params:
		arr = Array to search.
		a   = The elements to search for.

	Returns:
		Slice of `arr`.
 */
R[] takeUntilAny(R)(ref R[] arr, R[] a)
{
	foreach (size_t i, e; arr)
	{
		if (a.any!((x) => x == e))
		{
			auto result = arr[0 .. i];
			arr = arr[(i > $ ? $ : i) .. $];
			return result;
		}
	}

	return arr;
}

/**
	Returns a slice of `arr` from 0 until the last index where `pred` is satisfied.
	`arr` is narrowed to the range after that point.

	Params:
		pred = Predicate.
		arr  = Array to search.

	Returns:
		Slice of `arr`.
 */
R[] takeWhile(alias pred, R)(ref R[] arr)
{
	foreach (size_t i, e; arr)
	{
		if (!pred(e))
		{
			auto result = arr[0 .. i];
			arr = arr[(i > $ ? $ : i) .. $];
			return result;
		}
	}

	return arr;
}

/**
	Returns a slice of `arr` from 0 until the index where `element` is no longer found.
	`arr` is narrowed to the range after that point.

	Params:
		arr     = Array to search.
		element = The element to search for.

	Returns:
		Slice of `arr`.
 */
R[] takeWhile(R)(ref R[] arr, in R element)
{
	foreach (size_t i, e; arr)
	{
		if (e == element)
		{
			continue;
		}

		auto result = arr[0 .. i];
		arr = arr[(i > $ ? $ : i) .. $];
		return result;
	}

	return arr;
}

/**
	Returns a slice of `arr` from 0 until the index where no elements of `a` are found.
	`arr` is narrowed to the range after that point.

	Params:
		arr = Array to search.
		a   = The elements to search for.

	Returns:
		Slice of `arr`.
 */
R[] takeWhileAny(R)(ref R[] arr, R[] a)
{
	foreach (size_t i, e; arr)
	{
		if (a.any!((x) => x == e))
		{
			continue;
		}

		auto result = arr[0 .. i];
		arr = arr[(i > $ ? $ : i) .. $];
		return result;
	}

	return arr;
}
