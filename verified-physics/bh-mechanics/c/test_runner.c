#include "bh_bridge.h"
#include <stdio.h>
#include <math.h>

#define TEST(name, cond) \
  do { if (cond) { printf("  ok  %s\n",name); pass++; } \
       else      { printf("  FAIL %s\n",name); fail++; } total++; } while(0)

int main(void) {
  int total=0, pass=0, fail=0;
  double k, s, o; bool f;
  printf("BH-MECHANICS-VERIFIED\n=====================\n\n");

  printf("Schwarzschild M=1.0\n");
  TEST("kappa=0.25",   bh_verify_schwarzschild(1.0,0.01,&k,&s,&f) && fabs(k-0.25)<1e-15);
  TEST("entropy=4pi",  fabs(s-4*M_PI)<1e-15);
  TEST("first law",    f);

  printf("\nSchwarszchild M=2.0\n");
  TEST("kappa=0.125",  bh_verify_schwarzschild(2.0,0.1,&k,&s,&f) && fabs(k-0.125)<1e-15);
  TEST("entropy=16pi", fabs(s-16*M_PI)<1e-15);

  printf("\nKerr M=1 a=0.5\n");
  double r = 1.0 + sqrt(0.75);
  TEST("kappa exact",  bh_verify_kerr(1.0,0.5,&k,&s,&o) && fabs(k-(r-1)/(2*r))<1e-15);
  TEST("entropy exact",fabs(s-2*M_PI*(r*r+0.25))<1e-15);
  TEST("omega exact",  fabs(o-0.5/(2*r))<1e-15);

  printf("\nKerr extremal M=a=1\n");
  TEST("kappa=0",      bh_verify_kerr(1.0,1.0,&k,&s,&o) && fabs(k)<1e-15);
  TEST("entropy=4pi",  fabs(s-4*M_PI)<1e-14);

  printf("\nLQG correction\n");
  TEST("A=4pi a=0.1 b=0", bh_verify_lqg(4*M_PI,0.1,0.0,&s) && fabs(s-(M_PI+0.1*log(4*M_PI)))<1e-15);

  printf("\nString correction\n");
  TEST("A=4pi g=0.1",  bh_verify_string(4*M_PI,0.1,&s) && fabs(s-(M_PI+0.1*sqrt(4*M_PI)))<1e-15);

  printf("\nError cases\n");
  TEST("M=0 rejected",    !bh_verify_schwarzschild(0.0,0,NULL,NULL,NULL));
  TEST("M<0 rejected",    !bh_verify_schwarzschild(-1.0,0,NULL,NULL,NULL));
  TEST("a>M rejected",    !bh_verify_kerr(1.0,2.0,NULL,NULL,NULL));
  TEST("A=0 LQG rejected",!bh_verify_lqg(0.0,0,0,NULL));

  printf("\n=========================\n%d/%d passed, %d failed\n=========================\n",pass,total,fail);
  return fail==0?0:1;
}
