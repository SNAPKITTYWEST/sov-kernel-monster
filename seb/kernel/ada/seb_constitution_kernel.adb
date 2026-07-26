-- SPARK Kernel implementation

package body Kernel
  with SPARK_Mode => On
is

   function Authorize (P : Proposal) return Verdict is
   begin
      if P.Precondition_Met then
         return Approved;
      else
         return Denied;
      end if;
   end Authorize;

   procedure Execute_Transition (P : Proposal; V : out Verdict) is
   begin
      V := Authorize (P);
   end Execute_Transition;

end Kernel;
