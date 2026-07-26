-- seb_lattice.ads
-- SEB Lattice Circuit — Ahmad Ali Parr, SnapKitty Collective 2026
-- SPARK 2014, Pure, No heap, No external deps
--
-- Compile: gnatmake -O2 -gnat2012 seb_lattice_test.adb seb_lattice.adb
-- GNATprove: gnatprove -P seb_lattice.gpr --level=4

package SEB_Lattice
  with SPARK_Mode => On,
       Pure
is
   --  Primitive types
   type Byte is mod 256
     with Size => 8;

   type Index32 is range 0 .. 31;
   type Index64 is range 0 .. 63;

   type Poly     is array (Index32) of Byte;
   type Payload  is array (Index64) of Byte;

   --  96-byte record
   type Record96 is record
      Data       : Payload;
      Commitment : Poly;
   end record
     with Size => 768;  -- 96 bytes = 768 bits

   pragma Compile_Time_Error
     (Record96'Size /= 768, "Record96 must be exactly 96 bytes");

   --  Genesis: all-zero commitment
   Genesis_Tip : constant Poly := (others => 0);

   --  Fixed public constants (frozen at genesis)
   K0 : constant Poly := (0 => 1, others => 0);   -- x^0 = 1
   K1 : constant Poly := (1 => 1, others => 0);   -- x^1
   K2 : constant Poly := (2 => 1, others => 0);   -- x^2

   --  GF(256) multiply: AES irreducible x^8+x^4+x^3+x+1 (0x11B)
   function GF256_Mul (X, Y : Byte) return Byte
     with Pure_Function,
          Global => null;

   --  Cyclic convolution in GF(256)[x]/(x^32+1)
   function Cyclic_Convolve (A, B : Poly) return Poly
     with Pure_Function,
          Global => null;

   --  Circuit: next = K0⊗prev XOR K1⊗b XOR K2⊗c
   --  Since K0=1: next = prev XOR K1⊗b XOR K2⊗c
   function Lattice_Commit (Prev : Poly; Data : Payload) return Poly
     with Pure_Function,
          Global => null;

   --  Constant-time equality
   function CT_EQ (A, B : Poly) return Boolean
     with Pure_Function,
          Global => null,
          Post => CT_EQ'Result = (A = B);

end SEB_Lattice;
