
! Linker stubs for external C functions referenced by jordan_block
! These are normally provided by the full ZMOS/Bifrost runtime

subroutine zmos_spectral_invariant() bind(C, name="zmos_spectral_invariant")
  implicit none
end subroutine

subroutine sov_bifrost_sign_scalar_() bind(C, name="sov_bifrost_sign_scalar_")
  implicit none
end subroutine

subroutine qmhes_mmp_multiplicity() bind(C, name="qmhes_mmp_multiplicity")
  implicit none
end subroutine

subroutine qmhes_mmp_bound() bind(C, name="qmhes_mmp_bound")
  implicit none
end subroutine

subroutine sndl_freshness_hash() bind(C, name="sndl_freshness_hash")
  implicit none
end subroutine

subroutine worm_get_latest_hash_() bind(C, name="worm_get_latest_hash_")
  implicit none
end subroutine

subroutine sov_bifrost_sign_bytes_() bind(C, name="sov_bifrost_sign_bytes_")
  implicit none
end subroutine
