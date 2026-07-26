--  Sovereign Event Bus (SEB) - Write-Ahead Log Specification
--  Ada 2012 / SPARK Level 4
--
--  mmap-backed persistent storage with WORM integrity.

pragma SPARK_Mode (On);

with SEB_Types;
use SEB_Types;

package SEB_WAL is

   --  No public operations; all access through SEB_Kernel interface
   --  This package is internal to the kernel implementation.

end SEB_WAL;
