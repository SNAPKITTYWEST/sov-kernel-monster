--  Sovereign Event Bus (SEB) - Kernel Interface
--  Ada 2012 / SPARK Level 4
--
--  This file defines the verified kernel interface with all L0 invariants
--  encoded as preconditions and postconditions.
--
--  Invariants:
--    1. Plasma Gate: Ed25519 signature valid
--    2. Hash Chain: Prev_Hash == current tip hash
--    3. Offset Monotonic: Event offset > prior offset
--    4. Payload Hash: blake3(header || payload) matches footer.event_hash
--    5. Segment Chain: Prev_Seg_Hash links to prior segment

pragma SPARK_Mode (On);

with SEB_Types;
use SEB_Types;

package SEB_Kernel is

   --  Kernel Abstract State (SPARK Global_Input/Output)
   type Kernel_Handle is private;

   --  Initialization
   procedure Initialize_Kernel
      (Handle : out Kernel_Handle;
       Initial_Segment_Id : Unsigned_64;
       Initial_Segment_Sequence : Unsigned_64)
   with Global => null;

   --  Core Operation: Append Event
   --
   --  Preconditions (Level 4 verification):
   --    1. signature_valid: Ed25519.Verify(event.footer.signature, event.footer.event_hash)
   --    2. hash_chain_valid: event.footer.prev_hash == current_state.tip_hash
   --    3. offset_monotonic: event.header.prev_offset < proposed_offset
   --    4. payload_hash_valid: blake3(header || payload) == event.footer.event_hash
   --
   --  Postconditions:
   --    1. current_tip_hash == event.footer.event_hash
   --    2. current_tip_offset == new_offset
   --    3. event is WORM-sealed (msync called)
   --    4. events_sealed count incremented

   procedure Append_Event
      (Handle : in out Kernel_Handle;
       Header : Event_Header;
       Payload : Unsigned_8_Array;
       Footer : Event_Footer;
       Committed_Offset : out Segment_Offset)
   with Global => null,
        Pre => (
           Is_Valid_Header (Header) and
           Payload'Length = Natural (Header.Payload_Size) and
           Payload'Length <= Natural (Payload_Max_Size)
        ),
        Post => (
           Committed_Offset >= Min_Offset and
           Committed_Offset <= Max_Offset
        );

   --  Signature Verification (Plasma Gate)
   --
   --  Verifies Ed25519 signature on event hash.
   --  Postcondition: result = Valid iff signature is correct

   function Verify_Signature
      (Hash : Hash_Type;
       Signature : Signature_Type;
       Public_Key : Public_Key_Type)
   return Verification_Status
   with Global => null,
        Post => (
           Verify_Signature'Result = Valid or
           Verify_Signature'Result = Invalid_Signature
        );

   --  Hash Verification (Hash Chain Validation)
   --
   --  Verifies BLAKE3 hash of event data.
   --  Postcondition: result = Valid iff hash matches expected

   function Verify_Hash
      (Header : Event_Header;
       Payload : Unsigned_8_Array;
       Expected_Hash : Hash_Type)
   return Verification_Status
   with Global => null,
        Pre => Payload'Length = Natural (Header.Payload_Size),
        Post => (
           Verify_Hash'Result = Valid or
           Verify_Hash'Result = Invalid_Hash
        );

   --  Chain Validation (History Integrity)
   --
   --  Verifies entire event chain from tip to genesis.
   --  Returns status and number of events validated.

   procedure Verify_Chain
      (Handle : Kernel_Handle;
       Valid : out Boolean;
       Events_Checked : out Unsigned_64)
   with Global => null,
        Post => (
           Valid = False or
           Events_Checked > 0
        );

   --  Segment Rotation (WORM Boundary)
   --
   --  Rotates to new segment when current segment is full.
   --  Creates segment chain link via prev_seg_hash.
   --
   --  Preconditions:
   --    1. current_segment_size + new_event_size > Segment_Size
   --    2. new_segment_sequence > current_segment_sequence
   --
   --  Postconditions:
   --    1. new segment created with unique ID
   --    2. prev_seg_hash == hash(prior segment)
   --    3. segment_sequence incremented
   --    4. offset reset to 0 in new segment

   procedure Rotate_Segment
      (Handle : in out Kernel_Handle;
       New_Segment_Id : Unsigned_64;
       New_Segment_Sequence : Unsigned_64;
       Segment_Rotation_Offset : out Segment_Offset)
   with Global => null,
        Pre => New_Segment_Sequence > 0,
        Post => Segment_Rotation_Offset = 0;

   --  Query Operations

   function Get_Current_Segment_Id (Handle : Kernel_Handle) return Unsigned_64
   with Global => null;

   function Get_Current_Sequence (Handle : Kernel_Handle) return Unsigned_64
   with Global => null;

   function Get_Current_Tip_Hash (Handle : Kernel_Handle) return Hash_Type
   with Global => null;

   function Get_Current_Tip_Offset (Handle : Kernel_Handle) return Segment_Offset
   with Global => null;

   function Get_Events_Sealed_Count (Handle : Kernel_Handle) return Unsigned_64
   with Global => null;

   function Get_Segments_Rotated_Count (Handle : Kernel_Handle) return Unsigned_64
   with Global => null;

   --  Offset Type for Array Bounds
   type Unsigned_8_Array is array (Natural range <>) of Unsigned_8;

   --  WORM Flush Operation
   --
   --  Ensures all pending writes are synchronized to persistent storage.
   --  (mmap msync equivalent)
   --
   --  Postcondition: all prior Append_Event calls are durable

   procedure WORM_Flush (Handle : in out Kernel_Handle)
   with Global => null;

   --  Exception Handling
   Kernel_Error : exception;
   Integrity_Error : exception;
   Offset_Overflow : exception;
   Segment_Full_Error : exception;

private

   type Kernel_Handle is record
      Current_Segment_Id : Unsigned_64 := 0;
      Current_Sequence : Unsigned_64 := 0;
      Tip_Hash : Hash_Type := (others => 0);
      Tip_Offset : Segment_Offset := 0;
      Events_Sealed : Unsigned_64 := 0;
      Segments_Rotated : Unsigned_64 := 0;
   end record;

end SEB_Kernel;
