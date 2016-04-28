import std.meta;

//import core.simd;

//version(LDC)
//{
//	import ldc.gccbuiltins_x86;
//}


//version(LDC)
//{
//	version(SSE42)
//	{
//		version = LDC_SSE42;
//	}
//}

version(X86)
	version = GeneralUnaligned;

//static __gshared immutable whiteSpacesSet0 = " \t\r\n\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable whiteSpacesSet1 = " \t\r\0\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable numberSet = "0123456789Ee+-.\0";
//static __gshared immutable digitSet = "0123456789\0";

//static __gshared immutable nullSeq = "null\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable trueSeq = "true\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable falseSeq = "false\0\0\0\0\0\0\0\0\0\0\0";

private template Iota(size_t i, size_t j)
{
    static assert(i <= j, "Iota: i should be less than or equal to j");
    static if (i == j)
        alias Iota = AliasSeq!();
    else
        alias Iota = AliasSeq!(i, Iota!(i + 1, j));
}

auto byLineValue(Chunks)(Chunks chunks, size_t initLength)
{
	static struct LineValue
	{
		private Asdf!(false, Chunks) asdf;
		private bool _empty, _nextEmpty;

		void popFront()
		{
			assert(!empty);
			if(_nextEmpty)
			{
				_empty = true;
				return;
			}
			asdf.oa.shift = 0;
			auto length = asdf.readValue;
			if(length > 0)
			{
				auto t = asdf.skipSpaces;
				if(t != '\n' && t != 0)
					length = -t;
				else if(t == 0)
				{
					_nextEmpty = true;
					return;
				}
			}
			if(length <= 0)
			{
				length = -length;
				asdf.oa.shift = 0;
				while(length != '\n' && length != 0)
				{
					length = asdf.pop;
				}
			}
			_nextEmpty = length ? asdf.refresh : 0;
		}

		auto front() @property
		{
			assert(!empty);
			return asdf.oa.result;
		}

		bool empty()
		{
			return _empty;
		}
	}
	LineValue ret; 
	if(chunks.empty)
	{
		ret._empty = ret._nextEmpty = true;
	}
	else
	{
		ret = LineValue(Asdf!(false, Chunks)(chunks.front, chunks, OutputArray(initLength)));
		ret.popFront;
	}
	return ret;
}

unittest
{
	import std.stdio;
	auto values = File("test.json").byChunk(4096).byLineValue(4096);
	foreach(val; values)
	{
		//writefln(" ^^ %s", val.length);
	}
}


auto asdf(bool includingN = true, Chunks)(Chunks chunks, ubyte[] front, size_t initLength)
{
	import std.format: format;
	auto c = Asdf!(includingN, Chunks)(front, chunks, OutputArray(initLength));
	auto r = c.readValue;
	if(r == 0)
		throw new Exception("Unexpected end of input");
	if(r < 0)
		throw new Exception("Unexpected character \\x%02X : %s".format(-r, cast(char)-r
			));
	return c.oa.result;
}

auto asdf(bool includingN = true, Chunks)(Chunks chunks, size_t initLength)
{
	return asdf!(includingN, Chunks)(chunks, chunks.front, initLength);
}

unittest
{
	import std.stdio;
	auto c = asdf(File("test.json").byChunk(4096), 4096);
	//writeln(c.length);
}

struct Asdf(bool includingN = true, Chunks)
{
	ubyte[] r;
	Chunks chunks;
	OutputArray oa;

	bool refresh() @property
	{
		if(r.length == 0)
		{
			assert(!chunks.empty);
			chunks.popFront;
			if(chunks.empty)
				return true;
			r = chunks.front;
		}
		return false;
	} 

	int front()
	{
		if(r.length == 0)
		{
			assert(!chunks.empty);
			chunks.popFront;
			if(chunks.empty)
			{
				return 0;  // unexpected end of input
			}
			r = chunks.front;
		}
		return r[0];
	}

	void popFront()
	{
		r = r[1 .. $];
	}

	int pop()
	{
		int ret = front;
		if(ret != 0) popFront;
		return ret;
	}

	int skipSpaces()
	{
		for(;;)
		{
			int c = pop;
			switch(c)
			{
				case  ' ':
				case '\t':
				case '\r':
				static if(includingN)
				{
					case '\n':
				}
					continue;
				default:
					return c;
			}
		}
	}

	sizediff_t readValue()
	{
		int c = skipSpaces;
		switch(c)
		{
			case 'n': return readWord!("ull" , 0x00);
			case 't': return readWord!("rue" , 0x01);
			case 'f': return readWord!("alse", 0x02);
			case '-':
			case '0':
			..
			case '9': return readNumberImpl(cast(ubyte)c);
			case '"': return readStringImpl;
			case '[': return readArrayImpl;
			case '{': return readObjectImpl;
			default :              return -c;
		}
	}

	sizediff_t readStringImpl()
	{
		oa.put1(0x05);
		auto s = oa.skip(4);
		uint len;
		int prev;
		for(;;)
		{
			int c = pop;
			if(c < ' ')
				return -c;
			if(c == '"' && prev != '\\')
			{
				oa.put4(len, s);
				return len + 5;
			}
			prev = c;
			oa.put1(cast(ubyte)c);
			len++;
		}
	}

	sizediff_t readKeyImpl()
	{
		auto s = oa.skip(1);
		uint len;
		int prev;
		for(;;)
		{
			int c = pop;
			if(c < ' ')
				return -c;
			if(c == '"' && prev != '\\')
			{
				oa.put1(cast(ubyte)len, s);
				return len + 1;
			}
			prev = c;
			oa.put1(cast(ubyte)c);
			len++;
		}
	}

	sizediff_t readNumberImpl(ubyte c)
	{
		oa.put1(0x03);
		auto s = oa.skip(1);
		uint len = 1;
		oa.put1(c);
		for(;;)
		{
			uint d = front;
			switch(d)
			{
				case '0':
				..
				case '9':
				case '-':
				case '+':
				case '.':
				case 'e':
				case 'E':
					popFront;
					oa.put1(cast(ubyte)d);
					len++;
					break;
				default :
					oa.put1(cast(ubyte)len, s);
					return len + 2;
			}
		}
	}

	sizediff_t readWord(string word, ubyte t)()
	{
		foreach(i; Iota!(0, word.length))
		{
			auto c = pop;
			if(c != word[i])
				return -c;
		}
		oa.put1(t);
		return 1;
	}

	sizediff_t readArrayImpl()
	{
		oa.put1(0x09);
		auto s = oa.skip(4);
		uint len;
		L: for(;;)
		{
			auto v = readValue;
			if(v <= 0)
			{
				if(-v == ']' && len == 0)
					break;
				return v;
			}
			len += v;

			auto c = skipSpaces;
			switch(c)
			{
				case ',': continue;
				case ']': break L;
				default : return -c;
			}
		}
		oa.put4(len, s);
		return len + 5;
	}

	sizediff_t readObjectImpl()
	{
		oa.put1(0x0A);
		auto s = oa.skip(4);
		uint len;
		L: for(;;)
		{
			auto c = skipSpaces;
			if(c == '"')
			{
				auto v = readKeyImpl;
				if(v <= 0)
				{
					return v;
				}
				len += v;
			}
			else
			if(c == '}' && len == 0)
			{
				break;
			}
			else
			{
				return -c;
			}

			c = skipSpaces;
			if(c != ':')
				return -c;

			auto v = readValue;
			if(v <= 0)
			{
				return v;
			}
			len += v;

			c = skipSpaces;
			switch(c)
			{
				case ',': continue;
				case '}': break L;
				default : return -c;
			}
		}
		oa.put4(len, s);
		return len + 5;
	}
}

struct OutputArray
{
	import std.experimental.allocator;
	import std.experimental.allocator.gc_allocator;

	ubyte[] array;
	size_t shift;

	auto result()
	{
		return array[0 .. shift];
	}

	this(size_t initialLength)
	{
		assert(initialLength >= 32);
		array = cast(ubyte[]) GCAllocator.instance.allocate(GCAllocator.instance.goodAllocSize(initialLength));
	}

	size_t skip(size_t len) @safe pure nothrow @nogc
	{
		auto ret = shift;
		shift += len;
		return ret;
	}

	void put1(ubyte b)
	{
		put1(b, shift);
		shift += 1;
	}

	void put4(uint b)
	{
		put4(b, shift);
		shift += 4;
	}

	version(SSE42)
	void put16(ubyte16 b, size_t len)
	{
		put16(b, len, shift);
	}

	void put1(ubyte b, size_t sh)
	{
		assert(sh <= array.length);
		if(sh == array.length)
			extend;
		array[sh] = b;
	}

	void put4(uint b, size_t sh)
	{
		immutable newShift = sh + 4;
		if(newShift > array.length)
			extend;

		version(GeneralUnaligned)
		{
			*cast(uint*) (array.ptr + sh) = b;
		}
		else
		version(LittleEndian)
		{
			array[sh + 0] = cast(ubyte) (b >> 0x00u);
			array[sh + 1] = cast(ubyte) (b >> 0x08u);
			array[sh + 2] = cast(ubyte) (b >> 0x10u);
			array[sh + 3] = cast(ubyte) (b >> 0x18u);
		}
		else
		{
			array[sh + 0] = cast(ubyte) (b >> 0x18u);
			array[sh + 1] = cast(ubyte) (b >> 0x10u);
			array[sh + 2] = cast(ubyte) (b >> 0x08u);
			array[sh + 3] = cast(ubyte) (b >> 0x00u);
		}
	}

	version(SSE42)
	void put16(ubyte16 b, size_t len)
	{
		if(shift + 16 > array.length)
			extend;
		__builtin_ia32_storedqu(array.ptr, b);
		shift += len;
	}

	private void extend()
	{
		size_t length = array.length * 2;
		void[] t = array;
		GCAllocator.instance.reallocate(t, array.length * 2);
		array = cast(ubyte[])t;
	}
}

version(APP)
void main(string[] args)
{
	import std.datetime;
	import std.conv;
	import std.stdio;
	auto values = File(args[1]).byChunk(4096).byLineValue(4096);
	size_t len;
	StopWatch sw;
	sw.start;
	foreach(val; values)
	{
		len += val.length;
	}
	sw.stop;
	writefln("%s bytes", len);
	writeln(sw.peek.to!Duration);
}
