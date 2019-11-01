module wasm_reader.reader;

import wasm_reader.leb;
import std.typecons;
import std.meta;
import std.traits;
import std.range;
import std.algorithm : copy;

version(unittest) {
  import unit_threaded;
}

struct encoding(T) { }
struct condition(string cond) { }
struct length(alias field) { }
struct positionMark(string name) { }

struct header {
  uint version_;
}

struct Section {
  static auto calcPayloadLength(ref Section section, size_t[string] marks) {
    if (section.id != 0)
      return section.payload_len;
    return section.payload_len - (marks["b"] - marks["a"]);
  }
  @encoding!varuint7
  uint id;
  @encoding!varuint32
  uint payload_len;
  @condition!"id == 0" {
    @positionMark!"a" @encoding!varuint32
      uint name_len;
    @length!"name_len"
      string name;
  }
  @positionMark!"b" @length!calcPayloadLength
  ubyte[] payload;
}

struct import_section {
  @encoding!varuint32
  uint count;
  @length!"count"
  import_entry[] entries;
}

enum external_kind : ubyte  {
  Function = 0,
    Table = 1,
    Memory = 2,
    Global = 3
}

@encoding!varint7
enum value_type : byte {
  i32 = -0x01,
    i64 = -0x02,
    f32 = -0x03,
    f64 = -0x04,
    anyfunc = -0x10,
    func = -0x20,
    empty = -0x40
}

struct resizable_limits {
  @encoding!varuint1 bool flags;
  @encoding!varuint32 uint initial;
  @condition!"flags == true" @varuint32 uint maximum;
}
@encoding!varint7
enum elem_type : byte {
  anyfunc = -0x10
}

struct global_type {
  value_type content_type;
  @encoding!varuint1 bool mutability;
}

struct table_type {
  elem_type element_type;
  resizable_limits limits;
}

struct memory_type {
  resizable_limits limits;
}
struct import_entry {
  @encoding!varuint32
  uint module_len;
  @length!"module_len"
  string module_str;
  @encoding!varuint32
  uint field_len;
  @length!"field_len"
  string field_str;
  external_kind kind;
  @condition!"kind == external_kind.Function" @encoding!varuint32 uint functionType;
  @condition!"kind == external_kind.Table" table_type tableType;
  @condition!"kind == external_kind.Memory" memory_type memoryType;
  @condition!"kind == external_kind.Global" global_type globalType;
}

struct Sections(Range) {
  private {
    Range range;
    bool initialized = false;
    Section section;
    void readSection() {
      section = range.read!Section;
      initialized = true;
    }
  }
  this(ref Range range) {
    this.range = range;
  }
  @property bool empty() {
    return range.empty;
  }
  Section front() {
    if (!initialized)
      readSection();
    return section;
  }
  void popFront() {
    readSection();
  }
}

static assert(isInputRange!(Sections!(ubyte[])));

auto readSections(Range)(auto ref Range range) {
  return Sections!(Range)(range);
}

@("file")
unittest {
  import std.stdio;
  import std.algorithm;
  import std.range : take;
  auto input = File("resource/example.wasm").byChunk(4096).joiner().drop(8);
  auto sections = input.readSections.take(2).array();
  sections.shouldEqual([Section(1, 29, 0, "", [6, 96, 0, 0, 96, 2, 127, 127, 1, 127, 96, 1, 127, 0, 96, 1, 127, 1, 127, 96, 1, 125, 1, 127, 96, 2, 127, 127, 0]), Section(2, 181, 0, "", [7, 3, 101, 110, 118, 26, 115, 112, 97, 115, 109, 95, 97, 100, 100, 80, 114, 105, 109, 105, 116, 105, 118, 101, 95, 95, 115, 116, 114, 105, 110, 103, 0, 1, 3, 101, 110, 118, 11, 99, 111, 110, 115, 111, 108, 101, 95, 108, 111, 103, 0, 2, 3, 101, 110, 118, 23, 115, 112, 97, 115, 109, 95, 97, 100, 100, 80, 114, 105, 109, 105, 116, 105, 118, 101, 95, 95, 105, 110, 116, 0, 3, 3, 101, 110, 118, 25, 115, 112, 97, 115, 109, 95, 97, 100, 100, 80, 114, 105, 109, 105, 116, 105, 118, 101, 95, 95, 102, 108, 111, 97, 116, 0, 4, 3, 101, 110, 118, 21, 68, 111, 99, 117, 109, 101, 110, 116, 95, 108, 111, 99, 97, 116, 105, 111, 110, 95, 71, 101, 116, 0, 5, 3, 101, 110, 118, 18, 115, 112, 97, 115, 109, 95, 114, 101, 109, 111, 118, 101, 79, 98, 106, 101, 99, 116, 0, 2, 3, 101, 110, 118, 6, 109, 101, 109, 111, 114, 121, 2, 0, 2])]);
}

struct RangeWithPosition(Range) if (is(ElementType!Range == ubyte)) {
  private { Range* range; size_t pos = 0; }
  this(Range* range) {
    this.range = range;
  }
  auto front() {
    return (*range).front();
  }
  auto empty() {
    return range.empty;
  }
  void popFront() {
    (*range).popFront();
    pos += 1;
  }
  auto getPosition() {
    return pos;
  }
}

template read(T) {
  import std.traits;
  T read(Range)(ref Range range, size_t cnt) if (isArray!T) {
    static if(is(T : U[], U)) {}
    static if (isAggregateType!U) {
      Unqual!U[] items = new Unqual!U[cnt];
      foreach(idx; 0..cnt) {
        items[idx] = .read!U(range);
      }
      return cast(T)items;
    } else {
      Unqual!U[] items = new Unqual!U[cnt];
      foreach(idx; 0..cnt) {
        items[idx] = range.front();
        range.popFront();
      }
      return cast(T)items;
    }
  }
  T read(Range)(auto ref Range plainRange) {
    static if (isAggregateType!T) {
      auto range = RangeWithPosition!Range(&plainRange);
      T t;
      size_t[string] marks;
      assert(range.getPosition() == 0);
      static foreach(field; T.tupleof) {{
          static if (hasUDA!(field, positionMark)) {
            alias positionMarks = getUDAs!(field, positionMark);
            static foreach(marker; positionMarks) {{
                enum mark = TemplateArgsOf!(marker)[0];
                marks[mark] = range.getPosition();
              }}
          }
          static if (hasUDA!(field, condition)) {
            alias conditions = getUDAs!(field, condition);
            static foreach(c; conditions) {{
                enum condition = TemplateArgsOf!(c)[0];
                mixin("if (t."~condition~") readMember!(field.stringof)(range, t, marks);");
              }}
          } else {
            readMember!(field.stringof)(range, t, marks);
          }
        }}
      return t;
    } else static if (is(T == enum)) {
      static if (hasUDA!(T, encoding)) {
        alias encodingType = TemplateArgsOf!(getUDAs!(T, encoding)[0])[0];
        return readEncoding!(encodingType, T)(plainRange);
      } else {
        T t;
        ubyte[] mem = (cast(ubyte[])(&t)[0..1]);
        foreach(idx; 0..mem.length) {
          mem[idx] = plainRange.front;
          plainRange.popFront();
        }
        return t;
      }
    } else {
      T t;
      ubyte[] mem = (cast(ubyte[])(&t)[0..1]);
      foreach(idx; 0..mem.length) {
        mem[idx] = plainRange.front;
        plainRange.popFront();
      }
      return t;
    }
  }
}

Type readEncoding(Encoding, Type, Range)(auto ref Range range) {
  return cast(Type)Encoding.decode(range);
}

template readMember(string name) {
  void readMember(Range, T)(auto ref Range range, ref T t, ref size_t[string] marks) {
    alias field = AliasSeq!(__traits(getMember, t, name))[0];
    alias Field = typeof(field);
    static if (is(Field : U[], U)) {
      assert(hasUDA!(field, length));
      alias lengths = getUDAs!(field, length);
      static if (is(typeof(TemplateArgsOf!(lengths[0])[0]) == string)) {
        enum length = TemplateArgsOf!(lengths[0])[0];
        size_t len = __traits(getMember, t, length);
        __traits(getMember, t, name) = read!(Field)(range, len);
      } else {
        alias lengthFun = TemplateArgsOf!(lengths[0])[0];
        size_t len = lengthFun(t, marks);
        __traits(getMember, t, name) = read!(Field)(range, len);
      }
    } else static if (hasUDA!(field, encoding)) {
      alias EncodingType = TemplateArgsOf!(getUDAs!(field, encoding)[0])[0];
      __traits(getMember, t, name) = readEncoding!(EncodingType, Field)(range);
    } else {
      __traits(getMember, t, name) = read!(Field)(range);
    }
  }
}

unittest {
  ubyte[] data = [0x01,'A',0x0,0x0,0x0,0x0,0x0,0x0,0x0];
  data.read!import_entry.shouldEqual(import_entry(1,"A",0,"",external_kind.Function,0));
}

unittest {
  ubyte[] data = [0x01, 0x1d, 0x06, 0x60, 0x01, 0x7f, 0x00, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f, 0x60, 0x01, 0x7f, 0x01, 0x7f, 0x60, 0x01, 0x7d, 0x01, 0x7f, 0x60, 0x02, 0x7f, 0x7f, 0x00, 0x60, 0x00, 0x00];
  data.read!Section.shouldEqual(Section(1, 29, 0, "", [6, 96, 1, 127, 0, 96, 2, 127, 127, 1, 127, 96, 1, 127, 1, 127, 96, 1, 125, 1, 127, 96, 2, 127, 127, 0, 96, 0, 0]));
  data.length.shouldEqual(0);
}

unittest {
  ubyte[] data = [0x00, 0x1d, 0x01, 65, 0x06, 0x60, 0x01, 0x7f, 0x00, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f, 0x60, 0x01, 0x7f, 0x01, 0x7f, 0x60, 0x01, 0x7d, 0x01, 0x7f, 0x60, 0x02, 0x7f, 0x7f, 0x00, 0x60, 0x00, 0x00];
  data.read!Section.shouldEqual(Section(0, 29, 1, "A", [6, 96, 1, 127, 0, 96, 2, 127, 127, 1, 127, 96, 1, 127, 1, 127, 96, 1, 125, 1, 127, 96, 2, 127, 127, 0, 96, 0, 0]));
  data.length.shouldEqual(0);
}

unittest {
  ubyte[] data = [0x02, 0xb5, 0x01, 0x07, 0x03, 0x65, 0x6e, 0x76, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00, 0x02, 0x03, 0x65, 0x6e, 0x76, 0x0b, 0x63, 0x6f, 0x6e, 0x73, 0x6f, 0x6c, 0x65, 0x5f, 0x6c, 0x6f, 0x67, 0x00, 0x00, 0x03, 0x65, 0x6e, 0x76, 0x1a, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x61, 0x64, 0x64, 0x50, 0x72, 0x69, 0x6d, 0x69, 0x74, 0x69, 0x76, 0x65, 0x5f, 0x5f, 0x73, 0x74, 0x72, 0x69, 0x6e, 0x67, 0x00, 0x01, 0x03, 0x65, 0x6e, 0x76, 0x12, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x72, 0x65, 0x6d, 0x6f, 0x76, 0x65, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x00, 0x03, 0x65, 0x6e, 0x76, 0x17, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x61, 0x64, 0x64, 0x50, 0x72, 0x69, 0x6d, 0x69, 0x74, 0x69, 0x76, 0x65, 0x5f, 0x5f, 0x69, 0x6e, 0x74, 0x00, 0x02, 0x03, 0x65, 0x6e, 0x76, 0x19, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x61, 0x64, 0x64, 0x50, 0x72, 0x69, 0x6d, 0x69, 0x74, 0x69, 0x76, 0x65, 0x5f, 0x5f, 0x66, 0x6c, 0x6f, 0x61, 0x74, 0x00, 0x03, 0x03, 0x65, 0x6e, 0x76, 0x15, 0x44, 0x6f, 0x63, 0x75, 0x6d, 0x65, 0x6e, 0x74, 0x5f, 0x6c, 0x6f, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x5f, 0x47, 0x65, 0x74, 0x00, 0x04];
  data.read!Section.shouldEqual(Section(2, 181, 0, "", [7, 3, 101, 110, 118, 6, 109, 101, 109, 111, 114, 121, 2, 0, 2, 3, 101, 110, 118, 11, 99, 111, 110, 115, 111, 108, 101, 95, 108, 111, 103, 0, 0, 3, 101, 110, 118, 26, 115, 112, 97, 115, 109, 95, 97, 100, 100, 80, 114, 105, 109, 105, 116, 105, 118, 101, 95, 95, 115, 116, 114, 105, 110, 103, 0, 1, 3, 101, 110, 118, 18, 115, 112, 97, 115, 109, 95, 114, 101, 109, 111, 118, 101, 79, 98, 106, 101, 99, 116, 0, 0, 3, 101, 110, 118, 23, 115, 112, 97, 115, 109, 95, 97, 100, 100, 80, 114, 105, 109, 105, 116, 105, 118, 101, 95, 95, 105, 110, 116, 0, 2, 3, 101, 110, 118, 25, 115, 112, 97, 115, 109, 95, 97, 100, 100, 80, 114, 105, 109, 105, 116, 105, 118, 101, 95, 95, 102, 108, 111, 97, 116, 0, 3, 3, 101, 110, 118, 21, 68, 111, 99, 117, 109, 101, 110, 116, 95, 108, 111, 99, 97, 116, 105, 111, 110, 95, 71, 101, 116, 0, 4]));
  data.length.shouldEqual(0);
}

unittest {
  ubyte[] data = [0x07, 0x03, 0x65, 0x6e, 0x76, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00, 0x02, 0x03, 0x65, 0x6e, 0x76, 0x0b, 0x63, 0x6f, 0x6e, 0x73, 0x6f, 0x6c, 0x65, 0x5f, 0x6c, 0x6f, 0x67, 0x00, 0x00, 0x03, 0x65, 0x6e, 0x76, 0x1a, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x61, 0x64, 0x64, 0x50, 0x72, 0x69, 0x6d, 0x69, 0x74, 0x69, 0x76, 0x65, 0x5f, 0x5f, 0x73, 0x74, 0x72, 0x69, 0x6e, 0x67, 0x00, 0x01, 0x03, 0x65, 0x6e, 0x76, 0x12, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x72, 0x65, 0x6d, 0x6f, 0x76, 0x65, 0x4f, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x00, 0x00, 0x03, 0x65, 0x6e, 0x76, 0x17, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x61, 0x64, 0x64, 0x50, 0x72, 0x69, 0x6d, 0x69, 0x74, 0x69, 0x76, 0x65, 0x5f, 0x5f, 0x69, 0x6e, 0x74, 0x00, 0x02, 0x03, 0x65, 0x6e, 0x76, 0x19, 0x73, 0x70, 0x61, 0x73, 0x6d, 0x5f, 0x61, 0x64, 0x64, 0x50, 0x72, 0x69, 0x6d, 0x69, 0x74, 0x69, 0x76, 0x65, 0x5f, 0x5f, 0x66, 0x6c, 0x6f, 0x61, 0x74, 0x00, 0x03, 0x03, 0x65, 0x6e, 0x76, 0x15, 0x44, 0x6f, 0x63, 0x75, 0x6d, 0x65, 0x6e, 0x74, 0x5f, 0x6c, 0x6f, 0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x5f, 0x47, 0x65, 0x74, 0x00, 0x04];
  data.read!import_section.shouldEqual(import_section(7, [import_entry(3, "env", 6, "memory", external_kind.Memory, 0, table_type(elem_type.anyfunc, resizable_limits(false, 0, 0)), memory_type(resizable_limits(false, 2, 0)), global_type(value_type.i32, false)), import_entry(3, "env", 11, "console_log", external_kind.Function, 0, table_type(elem_type.anyfunc, resizable_limits(false, 0, 0)), memory_type(resizable_limits(false, 0, 0)), global_type(value_type.i32, false)), import_entry(3, "env", 26, "spasm_addPrimitive__string", external_kind.Function, 1, table_type(elem_type.anyfunc, resizable_limits(false, 0, 0)), memory_type(resizable_limits(false, 0, 0)), global_type(value_type.i32, false)), import_entry(3, "env", 18, "spasm_removeObject", external_kind.Function, 0, table_type(elem_type.anyfunc, resizable_limits(false, 0, 0)), memory_type(resizable_limits(false, 0, 0)), global_type(value_type.i32, false)), import_entry(3, "env", 23, "spasm_addPrimitive__int", external_kind.Function, 2, table_type(elem_type.anyfunc, resizable_limits(false, 0, 0)), memory_type(resizable_limits(false, 0, 0)), global_type(value_type.i32, false)), import_entry(3, "env", 25, "spasm_addPrimitive__float", external_kind.Function, 3, table_type(elem_type.anyfunc, resizable_limits(false, 0, 0)), memory_type(resizable_limits(false, 0, 0)), global_type(value_type.i32, false)), import_entry(3, "env", 21, "Document_location_Get", external_kind.Function, 4, table_type(elem_type.anyfunc, resizable_limits(false, 0, 0)), memory_type(resizable_limits(false, 0, 0)), global_type(value_type.i32, false))]));
  data.length.shouldEqual(0);
}
