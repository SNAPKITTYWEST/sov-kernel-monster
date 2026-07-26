-- seb_lattice.adb
-- SEB Lattice Circuit — body
-- SPARK 2014, Pure, constant-time arithmetic only

package body SEB_Lattice
  with SPARK_Mode => On
is

   --  GF(256) multiply with AES poly 0x1B (0x11B without the x^8 term)
   function GF256_Mul (X, Y : Byte) return Byte is
      Z  : Byte := 0;
      XX : Byte := X;
      YY : Byte := Y;
      Hi : Byte;
   begin
      for I in 0 .. 7 loop
         if (YY and 1) = 1 then
            Z := Z xor XX;
         end if;
         Hi := XX and 16#80#;
         XX := XX * 2;          --  left shift by 1
         if Hi /= 0 then
            XX := XX xor 16#1B#;
         end if;
         YY := YY / 2;          --  right shift by 1
      end loop;
      return Z;
   end GF256_Mul;

   --  Cyclic convolution: C[k] = XOR_{i=0..31} A[i] * B[(k-i) mod 32]
   function Cyclic_Convolve (A, B : Poly) return Poly is
      C   : Poly := (others => 0);
      Sum : Byte;
      J   : Index32;
   begin
      for K in Index32 loop
         Sum := 0;
         for I in Index32 loop
            J := Index32 ((Integer (K) - Integer (I) + 32) mod 32);
            Sum := Sum xor GF256_Mul (A (I), B (J));
         end loop;
         C (K) := Sum;
      end loop;
      return C;
   end Cyclic_Convolve;

   --  Circuit
   function Lattice_Commit (Prev : Poly; Data : Payload) return Poly is
      B  : Poly;
      C  : Poly;
      T0 : Poly;
      T1 : Poly;
      T2 : Poly;
      R  : Poly;
   begin
      --  Split payload into two 32-byte halves
      for I in Index32 loop
         B (I) := Data (Index64 (I));
         C (I) := Data (Index64 (Integer (I) + 32));
      end loop;

      T0 := Cyclic_Convolve (K0, Prev);
      T1 := Cyclic_Convolve (K1, B);
      T2 := Cyclic_Convolve (K2, C);

      for I in Index32 loop
         R (I) := T0 (I) xor T1 (I) xor T2 (I);
      end loop;
      return R;
   end Lattice_Commit;

   --  Constant-time equality: accumulate XOR, check zero
   function CT_EQ (A, B : Poly) return Boolean is
      Diff : Byte := 0;
   begin
      for I in Index32 loop
         Diff := Diff or (A (I) xor B (I));
      end loop;
      return Diff = 0;
   end CT_EQ;

end SEB_Lattice;
