// ==== FILE: rob_if.sv — PHẦN SỬA: mon_cb clocking block ====
//
// THAY ĐỔI: Thêm lxcpt_valid vào mon_cb để coverage có thể
// phân loại exception_type (dispatch_xcpt vs lxcpt vs csr_replay)
//
// Tìm đoạn mon_cb cũ trong rob_if.sv và thay bằng đoạn dưới:

  // ---- Monitor Clocking Block ----
  clocking mon_cb @(posedge clock);
    default input #1;
    // Dispatch
    input  enq_valids, enq_partial_stall;
    input  enq_uops_rob_idx, enq_uops_pdst, enq_uops_stale_pdst;
    input  enq_uops_exception, enq_uops_exc_cause;
    input  enq_uops_is_br, enq_uops_br_mask;
    input  enq_uops_is_fence, enq_uops_is_fencei, enq_uops_is_unique;
    input  enq_uops_unsafe, enq_uops_uses_ldq, enq_uops_uses_stq;
    input  enq_uops_flush_on_commit;
    input  enq_uops_ldst, enq_uops_ldst_val, enq_uops_fp_val;
    // Branch
    input  brupdate_b1_resolve_mask, brupdate_b1_mispredict_mask;
    input  brupdate_b2_mispredict, brupdate_b2_uop_rob_idx;
    // Writeback
    input  wb_resps_valid, wb_resps_rob_idx, wb_resps_pdst, wb_resps_predicated;
    // LSU
    input  lsu_clr_bsy_valid, lsu_clr_bsy_bits;
    // FFlags
    input  fflags_valid, fflags_uop_rob_idx, fflags_bits_flags;
    // Load exception  ← MỚI: coverage cần để phân loại xcpt_type
    input  lxcpt_valid;
    input  lxcpt_bits_uop_rob_idx;
    input  lxcpt_bits_cause;
    // Pointers
    input  rob_tail_idx, rob_head_idx;
    // Commit
    input  commit_valids, commit_arch_valids, commit_rbk_valids, commit_rollback;
    input  commit_uops_pdst, commit_uops_stale_pdst;
    // Exception & Flush
    input  com_xcpt_valid, com_xcpt_bits_cause, com_xcpt_bits_badvaddr;
    input  flush_valid, flush_bits_flush_typ, flush_frontend;
    // Status
    input  empty, ready;
    // FFlags commit
    input  commit_fflags_valid, commit_fflags_bits;
    // CSR  ← MỚI: coverage cần để sample csr_stall trực tiếp thay vì probe
    input  csr_stall;
  endclocking
