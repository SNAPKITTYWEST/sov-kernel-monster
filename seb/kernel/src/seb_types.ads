--  SEB_Types — Canonical Wire Types
--  Ada 2012 / SPARK Level 4
--  No Ada.Types (nonexistent). Uses Interfaces for Unsigned_N.
--  Wire layout verified: Header=68, Footer=128, Segment_Hdr=64.

pragma SPARK_Mode (On);

with Interfaces;
use Interfaces;

package SEB_Types is
   pragma Pure;

   --  Re-export Interfaces unsigned types with SEB names
   subtype Unsigned_8  is Interfaces.Unsigned_8;
   subtype Unsigned_16 is Interfaces.Unsigned_16;
   subtype Unsigned_32 is Interfaces.Unsigned_32;
   subtype Unsigned_64 is Interfaces.Unsigned_64;

   --  Cryptographic constants
   Hash_Size_Bytes      : constant := 32;
   Signature_Size_Bytes : constant := 64;
   Public_Key_Size      : constant := 32;

   --  Wire layout constants (verified component sums)
   Fixed_Header_Size   : constant := 68;         -- 8+8+8+4+4+8+8+8+4+4 = 68
   Fixed_Footer_Size   : constant := 128;        -- 32+32+64 = 128
   Segment_Header_Size : constant := 64;         -- 8+8+32+8+8 = 64
   Segment_Size        : constant := 1_073_741_824;  -- 1 GiB

   Fixed_Overhead     : constant := Fixed_Header_Size + Fixed_Footer_Size;  -- 196
   Payload_Region_Size : constant := Segment_Size - Segment_Header_Size;    -- 1_073_741_760
   Payload_Max_Size    : constant := Payload_Region_Size - Fixed_Overhead;  -- 1_073_741_564

   --  Offset and size types
   type Segment_Offset is new Unsigned_64;
   Min_Offset : constant Segment_Offset := 0;
   Max_Offset : constant Segment_Offset := Segment_Offset (Segment_Size - 1);

   --  Array types
   type Hash_Type       is array (1 .. Hash_Size_Bytes)      of Unsigned_8;
   type Signature_Type  is array (1 .. Signature_Size_Bytes) of Unsigned_8;
   type Public_Key_Type is array (1 .. Public_Key_Size)      of Unsigned_8;
   type Unsigned_8_Array is array (Natural range <>) of Unsigned_8;

   pragma Pack (Hash_Type);
   pragma Pack (Signature_Type);
   pragma Pack (Public_Key_Type);

   Genesis_Hash : constant Hash_Type := (others => 0);

   --  Event Header (68 bytes)
   --    Offset  Bytes  Field
   --     0       8     Event_Type_Id   (Unsigned_64)
   --     8       8     Timestamp_Ns    (Unsigned_64)
   --    16       8     Agent_Id        (Unsigned_64)
   --    24       4     Payload_Size    (Unsigned_32)
   --    28       4     Partition_Id    (Unsigned_32)
   --    32       8     Prev_Offset     (Unsigned_64)
   --    40       8     Sequence_No     (Unsigned_64)
   --    48       8     Reserved        (Unsigned_64)
   --    56       4     Reserved2       (Unsigned_32)
   --    60       4     Reserved3       (Unsigned_32)   = 68
   type Event_Header is record
      Event_Type_Id : Unsigned_64;
      Timestamp_Ns  : Unsigned_64;
      Agent_Id      : Unsigned_64;
      Payload_Size  : Unsigned_32;
      Partition_Id  : Unsigned_32;
      Prev_Offset   : Unsigned_64;
      Sequence_No   : Unsigned_64;
      Reserved      : Unsigned_64;
      Reserved2     : Unsigned_32;
      Reserved3     : Unsigned_32;
   end record
     with Convention => C, Pack => True,
          Size => Fixed_Header_Size * 8;

   --  Event Footer (128 bytes)
   --    Offset  Bytes  Field
   --     0      32     Prev_Hash   (Hash_Type)
   --    32      32     Event_Hash  (Hash_Type)
   --    64      64     Signature   (Signature_Type)  = 128
   type Event_Footer is record
      Prev_Hash  : Hash_Type;
      Event_Hash : Hash_Type;
      Signature  : Signature_Type;
   end record
     with Convention => C, Pack => True,
          Size => Fixed_Footer_Size * 8;

   --  Segment Header (64 bytes)
   --    Offset  Bytes  Field
   --     0       8     Segment_Id       (Unsigned_64)
   --     8       8     Segment_Sequence (Unsigned_64)
   --    16      32     Prev_Seg_Hash    (Hash_Type)
   --    48       8     Segment_Used     (Unsigned_64)
   --    56       8     Start_Offset     (Unsigned_64)  = 64
   type Segment_Header is record
      Segment_Id       : Unsigned_64;
      Segment_Sequence : Unsigned_64;
      Prev_Seg_Hash    : Hash_Type;
      Segment_Used     : Unsigned_64;
      Start_Offset     : Unsigned_64;
   end record
     with Convention => C, Pack => True,
          Size => Segment_Header_Size * 8;

   --  Verification result (no exceptions as enum literals)
   type Verification_Status is
     (Valid,
      Invalid_Signature,
      Invalid_Hash,
      Invalid_Offset,
      Invalid_Sequence,
      Replay_Detected,
      Segment_Full,
      Unknown_Error);

   --  Pure predicates
   function Is_Valid_Header (H : Event_Header) return Boolean is
     (H.Payload_Size > 0
      and H.Payload_Size <= Unsigned_32 (Payload_Max_Size));
   pragma Inline (Is_Valid_Header);

   function Is_Valid_Offset (O : Segment_Offset) return Boolean is
     (O >= Min_Offset and O <= Max_Offset);
   pragma Inline (Is_Valid_Offset);

   function Event_Total_Size (H : Event_Header) return Unsigned_64 is
     (Unsigned_64 (Fixed_Header_Size + Fixed_Footer_Size) + Unsigned_64 (H.Payload_Size));
   pragma Inline (Event_Total_Size);

   --  Chain integrity predicate
   function Chain_Intact (Prev_Hash : Hash_Type; Tip : Hash_Type) return Boolean is
     (Prev_Hash = Tip);
   pragma Inline (Chain_Intact);

end SEB_Types;
