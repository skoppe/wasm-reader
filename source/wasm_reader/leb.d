module wasm_reader.leb;

import std.range : ElementType, front, empty, popFront;

version(unittest) {
  import unit_threaded;
}

struct varuint(T) {
  static T decode(Range)(auto ref Range range) {
    return range.decodeLEBunsigned!T;
  }
}
struct varint(T) {
  static T decode(Range)(auto ref Range range) {
    return range.decodeLEBsigned!T;
  }
}

alias varuint1 = varuint!bool;
alias varuint7 = varuint!ubyte;
alias varuint32 = varuint!uint;
alias varint7 = varint!byte;
alias varint32 = varint!int;
alias varint64 = varint!long;

T decodeLEBsigned(T, Range)(auto ref Range range) if (is(ElementType!(Range) == ubyte)) {
  T result = 0;
  size_t shift = 0;
  enum size = T.sizeof * 8;
  ubyte b = 0;
  while(!range.empty) {
    b = range.front();
    range.popFront();
    result |= ((b & 0x7f) << shift);
    shift += 7;
    if ((b & 0x80) == 0)
      break;
  }

  if ((shift < size) && (b & 0x40))
    result |= (~0 << shift);
  return result;
}

unittest {
  import std.stdio;
  ubyte[] data = [0x9B,0xF1,0x59];
  assert(data.decodeLEBsigned!int() == -624485);
  assert(data.empty);
}

T decodeLEBunsigned(T, Range)(auto ref Range range) if (is(ElementType!(Range) == ubyte)) {
  T result = 0;
  size_t shift = 0;
  while(!range.empty) {
    ubyte b = range.front();
    range.popFront();
    static if (T.sizeof < 2) {
      result = cast(T)(b & 0x7f);
    } else
      result |= ((b & 0x7f) << shift);
    if ((b & 0x80) == 0)
      break;
    shift += 7;
  }
  return result;
}

unittest {
  ubyte[] data = [0xe5,0x8e,0x26];
  assert(data.decodeLEBunsigned!uint() == 624485);
  assert(data.empty);
}

unittest {
  ubyte[] data = [0x00];
  assert(data.decodeLEBunsigned!bool() == false);
  assert(data.empty);
}

unittest {
  ubyte[] data = [0x01];
  assert(data.decodeLEBunsigned!bool() == true);
  assert(data.empty);
}
