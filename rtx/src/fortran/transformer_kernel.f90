module transformer_kernel
    use iso_c_binding
    implicit none

    integer, parameter :: JANET_SLOTS  = 32
    integer, parameter :: KV_BLOCK_SIZE = 16

    type, bind(C) :: janet_array_t
        integer(c_int32_t) :: type_tag
        integer(c_int32_t) :: length
        integer(c_int32_t) :: capacity
        real(c_float)      :: data(JANET_SLOTS)
    end type janet_array_t

contains

    subroutine rmsnorm_fused(x, weight, out, n, eps) bind(C, name="rmsnorm_fused")
        real(c_float), intent(in)  :: x(*)
        real(c_float), intent(in)  :: weight(*)
        real(c_float), intent(out) :: out(*)
        integer(c_int32_t), value  :: n
        real(c_float),      value  :: eps
        real(c_float) :: sum_sq, inv_rms
        integer :: i
        sum_sq = 0.0_c_float
        do i = 1, n
            sum_sq = sum_sq + x(i) * x(i)
        end do
        inv_rms = 1.0_c_float / sqrt(sum_sq / real(n, c_float) + eps)
        do i = 1, n
            out(i) = x(i) * inv_rms * weight(i)
        end do
    end subroutine rmsnorm_fused

    subroutine silu_fused(x, out, n) bind(C, name="silu_fused")
        real(c_float), intent(in)  :: x(*)
        real(c_float), intent(out) :: out(*)
        integer(c_int32_t), value  :: n
        integer :: i
        do i = 1, n
            out(i) = x(i) / (1.0_c_float + exp(-x(i)))
        end do
    end subroutine silu_fused

    subroutine rope_fused(x, cos_c, sin_c, out, seq_len, n_heads, head_dim) bind(C, name="rope_fused")
        real(c_float), intent(in)  :: x(*)
        real(c_float), intent(in)  :: cos_c(*)
        real(c_float), intent(in)  :: sin_c(*)
        real(c_float), intent(out) :: out(*)
        integer(c_int32_t), value  :: seq_len, n_heads, head_dim
        integer :: s, h, d, idx, half_dim
        real(c_float) :: x1, x2, c, sv
        half_dim = head_dim / 2
        do s = 0, seq_len - 1
            do h = 0, n_heads - 1
                do d = 0, half_dim - 1
                    idx = (s * n_heads + h) * head_dim + d + 1
                    x1 = x(idx)
                    x2 = x(idx + half_dim)
                    c  = cos_c(s * half_dim + d + 1)
                    sv = sin_c(s * half_dim + d + 1)
                    out(idx)            = x1 * c  - x2 * sv
                    out(idx + half_dim) = x1 * sv + x2 * c
                end do
            end do
        end do
    end subroutine rope_fused

    subroutine gqa_attention_paged(q, block_table, kv_store, out, &
            n_seqs, n_heads, n_kv_heads, head_dim, block_size) &
            bind(C, name="gqa_attention_paged")
        real(c_float),    intent(in)  :: q(*)
        integer(c_int32_t), intent(in) :: block_table(*)
        real(c_float),    intent(in)  :: kv_store(*)
        real(c_float),    intent(out) :: out(*)
        integer(c_int32_t), value :: n_seqs, n_heads, n_kv_heads, head_dim, block_size
        integer :: seq, h, kv_h, b, t, d, q_idx, kv_idx, block_id
        real(c_float) :: scale, score, max_score, sum_exp, acc
        real(c_float), allocatable :: scores(:), attn(:)
        scale = 1.0_c_float / sqrt(real(head_dim, c_float))
        allocate(scores(block_size * KV_BLOCK_SIZE))
        allocate(attn(block_size * KV_BLOCK_SIZE))
        do seq = 0, n_seqs - 1
            do h = 0, n_heads - 1
                kv_h = h * n_kv_heads / n_heads
                max_score = -huge(0.0_c_float)
                do b = 0, block_size - 1
                    block_id = block_table(seq * block_size + b + 1)
                    if (block_id == -1) cycle
                    do t = 0, KV_BLOCK_SIZE - 1
                        score = 0.0_c_float
                        do d = 0, head_dim - 1
                            q_idx  = (seq * n_heads + h) * head_dim + d + 1
                            kv_idx = (block_id * n_kv_heads + kv_h) * head_dim * KV_BLOCK_SIZE &
                                   + t * head_dim + d + 1
                            score = score + q(q_idx) * kv_store(kv_idx)
                        end do
                        score = score * scale
                        scores(b * KV_BLOCK_SIZE + t + 1) = score
                        if (score > max_score) max_score = score
                    end do
                end do
                sum_exp = 0.0_c_float
                do b = 0, block_size - 1
                    block_id = block_table(seq * block_size + b + 1)
                    if (block_id == -1) cycle
                    do t = 0, KV_BLOCK_SIZE - 1
                        attn(b * KV_BLOCK_SIZE + t + 1) = exp(scores(b * KV_BLOCK_SIZE + t + 1) - max_score)
                        sum_exp = sum_exp + attn(b * KV_BLOCK_SIZE + t + 1)
                    end do
                end do
                do d = 0, head_dim - 1
                    acc = 0.0_c_float
                    do b = 0, block_size - 1
                        block_id = block_table(seq * block_size + b + 1)
                        if (block_id == -1) cycle
                        do t = 0, KV_BLOCK_SIZE - 1
                            kv_idx = (block_id * n_kv_heads + kv_h) * head_dim * KV_BLOCK_SIZE &
                                   + t * head_dim + d + 1
                            acc = acc + (attn(b * KV_BLOCK_SIZE + t + 1) / sum_exp) * kv_store(kv_idx)
                        end do
                    end do
                    q_idx = (seq * n_heads + h) * head_dim + d + 1
                    out(q_idx) = acc
                end do
            end do
        end do
        deallocate(scores, attn)
    end subroutine gqa_attention_paged

    subroutine kv_init() bind(C, name="kv_init")
    end subroutine kv_init

    subroutine kv_allocate_blocks(num_blocks, layer, head_dim) bind(C, name="kv_allocate_blocks")
        integer(c_int32_t), value :: num_blocks, layer, head_dim
    end subroutine kv_allocate_blocks

    subroutine kv_append_tokens(seq_id, layer, k, v, num_tokens) bind(C, name="kv_append_tokens")
        integer(c_int32_t), value  :: seq_id, layer, num_tokens
        real(c_float), intent(in)  :: k(*), v(*)
    end subroutine kv_append_tokens

    subroutine blake3_hash_kv(kv_store, seq_id, out_hash) bind(C, name="blake3_hash_kv")
        real(c_float),      intent(in)  :: kv_store(*)
        integer(c_int32_t), value       :: seq_id
        integer(c_uint8_t), intent(out) :: out_hash(32)
        integer :: i
        ! Stub: wire to sov_blake3_* from sov_monster_kernel.f90
        do i = 1, 32
            out_hash(i) = 0
        end do
    end subroutine blake3_hash_kv

    subroutine ed25519_sign_fortran(message, msglen, sk, signature) bind(C, name="ed25519_sign_fortran")
        integer(c_uint8_t), intent(in)  :: message(*)
        integer(c_int32_t), value       :: msglen
        integer(c_uint8_t), intent(in)  :: sk(32)
        integer(c_uint8_t), intent(out) :: signature(64)
        integer :: i
        ! Stub: wire to sov_bifrost_sign from sov_monster_kernel.f90
        do i = 1, 64
            signature(i) = 0
        end do
    end subroutine ed25519_sign_fortran

end module transformer_kernel
