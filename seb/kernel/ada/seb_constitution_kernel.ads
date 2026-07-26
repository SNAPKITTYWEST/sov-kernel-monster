-- SPARK Kernel — verified execution authority
-- Contracts enforce: no transition without valid capability + precondition

package Kernel
  with SPARK_Mode => On
is

   type Actor_ID is range 1 .. 1000;
   type Target_ID is range 1 .. 1000;
   type Capability is (Execute, Write, Read, Verify, Observe, Vacuum_Collapse);

   type Proposal is record
      Actor       : Actor_ID;
      Cap         : Capability;
      Target      : Target_ID;
      Precondition_Met : Boolean;
   end record;

   type Verdict is (Approved, Denied);

   function Authorize (P : Proposal) return Verdict
     with Post => (if P.Precondition_Met then Authorize'Result = Approved
                   else Authorize'Result = Denied);

   procedure Execute_Transition (P : Proposal; V : out Verdict)
     with Pre => P.Precondition_Met = True,
          Post => V = Approved;

end Kernel;
