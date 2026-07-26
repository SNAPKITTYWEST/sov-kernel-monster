-- seb_lattice_test.adb
-- Conformance test: reads vectors.bin, verifies Lattice_Commit.
-- Each vector: prev[32] + payload[64] + expected[32] = 128 bytes.
--
-- Compile: gnatmake -O2 -gnat2012 seb_lattice_test.adb
-- Run:     ./seb_lattice_test vectors.bin
-- Pass:    "20/20 PASS"

with SEB_Lattice; use SEB_Lattice;
with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams.Stream_IO;

procedure SEB_Lattice_Test is
   use Ada.Text_IO;
   use Ada.Streams.Stream_IO;

   subtype Raw32 is SEB_Lattice.Poly;
   subtype Raw64 is SEB_Lattice.Payload;

   --  Read exactly N bytes from stream into array
   procedure Read_Poly (S : Stream_Access; P : out Raw32) is
   begin
      for I in Raw32'Range loop
         SEB_Lattice.Byte'Read (S, P (I));
      end loop;
   end Read_Poly;

   procedure Read_Payload (S : Stream_Access; P : out Raw64) is
   begin
      for I in Raw64'Range loop
         SEB_Lattice.Byte'Read (S, P (I));
      end loop;
   end Read_Payload;

   File    : Ada.Streams.Stream_IO.File_Type;
   S       : Stream_Access;
   Pass    : Natural := 0;
   Fail    : Natural := 0;
   N       : Natural := 0;

   Prev     : Raw32;
   Pay      : Raw64;
   Expected : Raw32;
   Got      : Raw32;

begin
   if Ada.Command_Line.Argument_Count < 1 then
      Put_Line ("usage: seb_lattice_test vectors.bin");
      Ada.Command_Line.Set_Exit_Status (1);
      return;
   end if;

   Open (File, In_File, Ada.Command_Line.Argument (1));
   S := Stream (File);

   loop
      begin
         Read_Poly    (S, Prev);
         Read_Payload (S, Pay);
         Read_Poly    (S, Expected);
      exception
         when End_Error => exit;
      end;

      Got := Lattice_Commit (Prev, Pay);

      if CT_EQ (Got, Expected) then
         Pass := Pass + 1;
      else
         Put ("FAIL vector "); Put (Natural'Image (N));
         New_Line;
         Fail := Fail + 1;
      end if;
      N := N + 1;
   end loop;

   Close (File);

   Put (Natural'Image (Pass) & "/" & Natural'Image (N) & " ");
   if Fail = 0 and N > 0 then
      Put_Line ("PASS");
   else
      Put_Line ("FAIL");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end SEB_Lattice_Test;
