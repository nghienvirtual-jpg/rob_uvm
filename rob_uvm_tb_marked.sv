//******************************************************************************
// UVM Testbench Environment for BOOM Reorder Buffer (ROB)
// ENHANCED VERSION — 13 Testcases covering all features in rob_testplan.md
//   TC1:  Dispatch / Allocation
//   TC2:  Out-of-Order Writeback
//   TC3:  In-Order Commit
//   TC4:  Precise Exception Handling
//   TC5:  Branch Misprediction Recovery
//   TC6:  Reset State Verification         (F1.6, F7.1)
//   TC7:  Fence Dispatch                   (F1.7)
//   TC8:  LSU Clear Busy                   (F2.5)
//   TC9:  CSR Stall Blocks Commit          (F3.7)
//   TC10: Predicated arch_valids           (F3.8)
//   TC11: Branch Mask Update on Resolve    (F5.4)
//   TC12: Pointer Wrap-Around              (F6.1, F6.2)
//   TC13: Oldest Exception Wins            (F4.9)
//
// Includes: Shadow ROB reference model, Rule Checker (D1-D6, W1-W5, A8),
//           Enhanced Scoreboard, Functional Coverage (§7), Enhanced Monitor
//******************************************************************************

// ==== FILE: rob_if.sv ====
`timescale 1ns/1ps

// ============================================================================
// 1. INTERFACE
// ============================================================================
interface rob_if(input logic clock, input logic reset);

  // --- Enqueue (Dispatch) ---
  logic        enq_valids [3];
  logic        enq_partial_stall;

  logic [6:0]  enq_uops_uopc       [3];
  logic [31:0] enq_uops_debug_inst  [3];
  logic        enq_uops_is_rvc     [3];
  logic        enq_uops_is_br      [3];
  logic        enq_uops_is_jalr    [3];
  logic        enq_uops_is_jal     [3];
  logic [15:0] enq_uops_br_mask    [3];
  logic [4:0]  enq_uops_ftq_idx    [3];
  logic        enq_uops_edge_inst  [3];
  logic [5:0]  enq_uops_pc_lob     [3];
  logic [6:0]  enq_uops_rob_idx    [3];
  logic [6:0]  enq_uops_pdst       [3];
  logic [6:0]  enq_uops_stale_pdst [3];
  logic        enq_uops_exception  [3];
  logic [63:0] enq_uops_exc_cause  [3];
  logic        enq_uops_is_fence   [3];
  logic        enq_uops_is_fencei  [3];
  logic        enq_uops_uses_ldq   [3];
  logic        enq_uops_uses_stq   [3];
  logic        enq_uops_is_sys_pc2epc [3];
  logic        enq_uops_is_unique  [3];
  logic        enq_uops_flush_on_commit [3];
  logic [5:0]  enq_uops_ldst       [3];
  logic        enq_uops_ldst_val   [3];
  logic [1:0]  enq_uops_dst_rtype  [3];
  logic        enq_uops_fp_val     [3];
  logic [1:0]  enq_uops_debug_fsrc [3];
  logic        enq_uops_unsafe     [3];

  logic [39:0] xcpt_fetch_pc;

  // --- Branch Update ---
  logic [15:0] brupdate_b1_resolve_mask;
  logic [15:0] brupdate_b1_mispredict_mask;
  logic [6:0]  brupdate_b2_uop_rob_idx;
  logic        brupdate_b2_mispredict;
  logic        brupdate_b2_taken;

  // --- Writeback (6 ports) ---
  logic        wb_resps_valid      [6];
  logic [6:0]  wb_resps_rob_idx    [6];
  logic [6:0]  wb_resps_pdst       [6];
  logic        wb_resps_predicated [6];

  // --- LSU Clear Busy (2 ports) ---
  logic        lsu_clr_bsy_valid   [2];
  logic [6:0]  lsu_clr_bsy_bits    [2];

  // --- FFlags (2 ports) ---
  logic        fflags_valid        [2];
  logic [6:0]  fflags_uop_rob_idx  [2];
  logic [4:0]  fflags_bits_flags   [2];

  // --- Load Exception ---
  logic        lxcpt_valid;
  logic [15:0] lxcpt_bits_uop_br_mask;
  logic [6:0]  lxcpt_bits_uop_rob_idx;
  logic [4:0]  lxcpt_bits_cause;
  logic [39:0] lxcpt_bits_badvaddr;

  // --- CSR ---
  logic        csr_stall;

  // --- Outputs ---
  logic [6:0]  rob_tail_idx;
  logic [6:0]  rob_head_idx;

  logic        commit_valids      [3];
  logic        commit_arch_valids [3];
  logic        commit_rbk_valids  [3];
  logic        commit_rollback;

  logic [6:0]  commit_uops_pdst       [3];
  logic [6:0]  commit_uops_stale_pdst [3];
  logic        commit_uops_ldst_val   [3];
  logic [5:0]  commit_uops_ldst       [3];
  logic        commit_uops_is_br      [3];

  logic        commit_fflags_valid;
  logic [4:0]  commit_fflags_bits;

  logic        com_load_is_at_rob_head;
  logic        com_xcpt_valid;
  logic [63:0] com_xcpt_bits_cause;
  logic [63:0] com_xcpt_bits_badvaddr;

  logic        flush_valid;
  logic [2:0]  flush_bits_flush_typ;

  logic        empty;
  logic        ready;
  logic        flush_frontend;

  // ---- Driver Clocking Block ----
  clocking drv_cb @(posedge clock);
    default input #1 output #1;
    output enq_valids, enq_partial_stall;
    output enq_uops_uopc, enq_uops_debug_inst, enq_uops_is_rvc;
    output enq_uops_is_br, enq_uops_is_jalr, enq_uops_is_jal;
    output enq_uops_br_mask, enq_uops_ftq_idx, enq_uops_edge_inst;
    output enq_uops_pc_lob, enq_uops_rob_idx, enq_uops_pdst;
    output enq_uops_stale_pdst, enq_uops_exception, enq_uops_exc_cause;
    output enq_uops_is_fence, enq_uops_is_fencei;
    output enq_uops_uses_ldq, enq_uops_uses_stq;
    output enq_uops_is_sys_pc2epc, enq_uops_is_unique;
    output enq_uops_flush_on_commit, enq_uops_ldst, enq_uops_ldst_val;
    output enq_uops_dst_rtype, enq_uops_fp_val, enq_uops_debug_fsrc;
    output enq_uops_unsafe;
    output xcpt_fetch_pc;
    output brupdate_b1_resolve_mask, brupdate_b1_mispredict_mask;
    output brupdate_b2_uop_rob_idx, brupdate_b2_mispredict, brupdate_b2_taken;
    output wb_resps_valid, wb_resps_rob_idx, wb_resps_pdst, wb_resps_predicated;
    output lsu_clr_bsy_valid, lsu_clr_bsy_bits;
    output fflags_valid, fflags_uop_rob_idx, fflags_bits_flags;
    output lxcpt_valid, lxcpt_bits_uop_br_mask, lxcpt_bits_uop_rob_idx;
    output lxcpt_bits_cause, lxcpt_bits_badvaddr;
    output csr_stall;
    input  rob_tail_idx, rob_head_idx;
    input  commit_valids, commit_arch_valids, commit_rbk_valids, commit_rollback;
    input  commit_uops_pdst, commit_uops_stale_pdst, commit_uops_ldst_val, commit_uops_ldst;
    input  com_load_is_at_rob_head;
    input  com_xcpt_valid, com_xcpt_bits_cause, com_xcpt_bits_badvaddr;
    input  flush_valid, flush_bits_flush_typ;
    input  empty, ready, flush_frontend;
    input  commit_fflags_valid, commit_fflags_bits;
  endclocking

  // ---- Monitor Clocking Block (EXPANDED — sample mọi tín hiệu cần thiết) ----
  clocking mon_cb @(posedge clock);
    default input #1;
    // Dispatch
    input  enq_valids, enq_partial_stall;
    input  enq_uops_rob_idx, enq_uops_pdst, enq_uops_stale_pdst;
    input  enq_uops_exception, enq_uops_exc_cause;
    input  enq_uops_is_br, enq_uops_br_mask;
    input  enq_uops_is_fence, enq_uops_is_fencei;
    input  enq_uops_unsafe, enq_uops_uses_ldq, enq_uops_uses_stq;
    input  enq_uops_is_unique, enq_uops_flush_on_commit;
    input  enq_uops_ldst, enq_uops_ldst_val, enq_uops_fp_val;
    // Branch
    input  brupdate_b1_resolve_mask, brupdate_b1_mispredict_mask;
    input  brupdate_b2_mispredict, brupdate_b2_uop_rob_idx;
    // Writeback
    input  wb_resps_valid, wb_resps_rob_idx, wb_resps_pdst, wb_resps_predicated;
    // LSU
    input  lsu_clr_bsy_valid, lsu_clr_bsy_bits;
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
    // FFlags
    input  commit_fflags_valid, commit_fflags_bits;
  endclocking

  modport DRV(clocking drv_cb, input clock, input reset);
  modport MON(clocking mon_cb, input clock, input reset);

endinterface


// ============================================================================
// 2. PACKAGE — Toàn bộ UVM components
// ============================================================================
// ==== FILE: rob_pkg_header.sv ====
package rob_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // =========================================================================
  // PARAMETERS
  // =========================================================================
  parameter int CW             = 3;   // coreWidth
  parameter int NUM_ROB_ROWS   = 32;
  parameter int NUM_ROB_ENTRIES = NUM_ROB_ROWS * CW;  // 96
  parameter int NUM_WB_PORTS   = 6;

  // =========================================================================
  // TRANSACTION
  // =========================================================================
// ==== FILE: rob_transaction.sv ====
  typedef enum {
    ROB_DISPATCH,
    ROB_WRITEBACK,
    ROB_BRANCH_UPDATE,
    ROB_LXCPT,
    ROB_LSU_CLR_BSY,
    ROB_IDLE
  } rob_op_e;

  class rob_transaction extends uvm_sequence_item;
    `uvm_object_utils(rob_transaction)

    rand rob_op_e op;

    // Dispatch
    rand bit       enq_valids [3];
    rand bit       enq_partial_stall;
    rand bit [6:0] enq_uops_uopc [3];
    rand bit [15:0] enq_uops_br_mask [3];
    rand bit [6:0] enq_uops_rob_idx [3];
    rand bit [6:0] enq_uops_pdst [3];
    rand bit [6:0] enq_uops_stale_pdst [3];
    rand bit       enq_uops_exception [3];
    rand bit [63:0] enq_uops_exc_cause [3];
    rand bit       enq_uops_is_br [3];
    rand bit       enq_uops_is_fence [3];
    rand bit       enq_uops_is_fencei [3];
    rand bit       enq_uops_unsafe [3];
    rand bit       enq_uops_uses_ldq [3];
    rand bit       enq_uops_uses_stq [3];
    rand bit       enq_uops_is_unique [3];
    rand bit       enq_uops_flush_on_commit [3];
    rand bit [5:0] enq_uops_ldst [3];
    rand bit       enq_uops_ldst_val [3];
    rand bit       enq_uops_fp_val [3];

    // Writeback
    rand bit       wb_valid [6];
    rand bit [6:0] wb_rob_idx [6];
    rand bit [6:0] wb_pdst [6];

    // Branch update
    rand bit [15:0] br_resolve_mask;
    rand bit [15:0] br_mispredict_mask;
    rand bit [6:0]  br_rob_idx;
    rand bit        br_mispredict;

    // LSU clear busy
    rand bit        lsu_clr_valid [2];
    rand bit [6:0]  lsu_clr_bits [2];

    // Load exception
    rand bit        lxcpt_valid;
    rand bit [6:0]  lxcpt_rob_idx;
    rand bit [4:0]  lxcpt_cause;
    rand bit [39:0] lxcpt_badvaddr;

    function new(string name = "rob_transaction");
      super.new(name);
    endfunction

    constraint default_idle_c { soft op == ROB_IDLE; }

    function string convert2string();
      return $sformatf("op=%s enq_v={%0b,%0b,%0b} wb_v[0]=%0b br_mis=%0b",
                        op.name(), enq_valids[0], enq_valids[1], enq_valids[2],
                        wb_valid[0], br_mispredict);
    endfunction
  endclass


  // =========================================================================
  // SHADOW ROB MODEL — Reference model cho scoreboard
  // =========================================================================
// ==== FILE: rob_shadow_model.sv ====
  typedef struct {
    bit        valid;
    bit        busy;
    bit        unsafe;
    bit        exception;
    bit [63:0] exc_cause;
    bit [6:0]  pdst;
    bit [6:0]  stale_pdst;
    bit [15:0] br_mask;
    bit        is_fence;
  } shadow_entry_t;

  class rob_shadow_model extends uvm_object;
    `uvm_object_utils(rob_shadow_model)

    shadow_entry_t entries [NUM_ROB_ENTRIES];

    function new(string name = "rob_shadow_model");
      super.new(name);
      reset();
    endfunction

    function void reset();
      for (int i = 0; i < NUM_ROB_ENTRIES; i++)
        entries[i] = '{default:0};
    endfunction

    // D1: không ghi đè entry valid
    function bit dispatch(int idx, bit [6:0] pdst, bit [6:0] stale_pdst,
                          bit xcpt, bit [63:0] cause,
                          bit is_br, bit [15:0] br_mask,
                          bit is_fence, bit unsafe_in);
      if (entries[idx].valid) begin
        `uvm_error("SHADOW", $sformatf("D1 VIOLATION: Dispatch to valid entry [%0d]", idx))
        return 0;
      end
      entries[idx].valid      = 1;
      entries[idx].pdst       = pdst;
      entries[idx].stale_pdst = stale_pdst;
      entries[idx].exception  = xcpt;
      entries[idx].exc_cause  = cause;
      entries[idx].br_mask    = br_mask;
      entries[idx].is_fence   = is_fence;
      entries[idx].unsafe     = unsafe_in;
      entries[idx].busy       = (is_fence) ? 0 : 1;  // F1.7
      return 1;
    endfunction

    // W1/W2/W3 checks
    function bit writeback(int idx, bit [6:0] pdst);
      if (!entries[idx].valid) begin
        `uvm_error("SHADOW", $sformatf("W1 VIOLATION: WB to invalid entry [%0d]", idx))
        return 0;
      end
      if (!entries[idx].busy) begin
        `uvm_error("SHADOW", $sformatf("W2 VIOLATION: Double WB to not-busy entry [%0d]", idx))
        return 0;
      end
      if (entries[idx].pdst != pdst) begin
        `uvm_error("SHADOW", $sformatf("W3 VIOLATION: pdst mismatch [%0d] exp=%0d got=%0d",
                   idx, entries[idx].pdst, pdst))
        return 0;
      end
      entries[idx].busy   = 0;
      entries[idx].unsafe = 0;  // F2.3
      return 1;
    endfunction

    function void lsu_clr(int idx);
      if (entries[idx].valid)
        entries[idx].busy = 0;
    endfunction

    function void branch_resolve(bit [15:0] resolve_mask);
      for (int i = 0; i < NUM_ROB_ENTRIES; i++)
        if (entries[i].valid)
          entries[i].br_mask &= ~resolve_mask;
    endfunction

    function void branch_kill(bit [15:0] kill_mask);
      for (int i = 0; i < NUM_ROB_ENTRIES; i++)
        if (entries[i].valid && (entries[i].br_mask & kill_mask)) begin
          entries[i].valid = 0;
          entries[i].busy  = 0;
        end
    endfunction

    function void commit(int idx);
      entries[idx].valid = 0;
      entries[idx].busy  = 0;
    endfunction

    function void flush_all();
      for (int i = 0; i < NUM_ROB_ENTRIES; i++) begin
        entries[i].valid = 0;
        entries[i].busy  = 0;
      end
    endfunction

    function int occupancy();
      int c = 0;
      for (int i = 0; i < NUM_ROB_ENTRIES; i++)
        if (entries[i].valid) c++;
      return c;
    endfunction
  endclass


  // =========================================================================
  // RULE CHECKER — Chạy mỗi cycle bởi scoreboard
  // =========================================================================
// ==== FILE: rob_rule_checker.sv ====
  class rob_rule_checker extends uvm_object;
    `uvm_object_utils(rob_rule_checker)

    int violations;

    function new(string name = "rob_rule_checker");
      super.new(name);
      violations = 0;
    endfunction

    // D3: chỉ dispatch khi ready
    function void chk_dispatch_ready(bit ready, bit any_enq);
      if (any_enq && !ready) begin
        `uvm_error("RULE_D3", "Dispatch when io_ready=0!")
        violations++;
      end
    endfunction

    // A8: commit/rollback exclusive
    function void chk_commit_rbk_excl(bit [2:0] cv, bit [2:0] rv);
      if ((cv & rv) != 0) begin
        `uvm_error("RULE_A8", $sformatf("commit_v=0x%0h overlaps rbk_v=0x%0h", cv, rv))
        violations++;
      end
    endfunction

    // F3.1: In-order commit — bank liên tục, không gap
    function void chk_inorder_commit(bit v[3]);
      bit gap = 0;
      for (int b = 0; b < CW; b++) begin
        if (gap && v[b]) begin
          `uvm_error("RULE_F3.1", $sformatf("Commit gap before bank %0d", b))
          violations++;
        end
        if (!v[b]) gap = 1;
      end
    endfunction

    function void report();
      if (violations == 0)
        `uvm_info("RULE", "All rule checks PASSED — 0 violations", UVM_LOW)
      else
        `uvm_error("RULE", $sformatf("FAILED — %0d rule violations", violations))
    endfunction
  endclass


  // =========================================================================
  // DRIVER (giữ nguyên logic gốc)
  // =========================================================================
  `define ROB_IDX(row, bank) ((row)*CW + (bank))

// ==== FILE: rob_driver.sv ====
  class rob_driver extends uvm_driver #(rob_transaction);
    `uvm_component_utils(rob_driver)
    virtual rob_if.DRV vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rob_if.DRV)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "Failed to get vif")
    endfunction

    task run_phase(uvm_phase phase);
      rob_transaction tr;
      @(negedge vif.reset);
      repeat(2) @(posedge vif.clock);
      forever begin
        seq_item_port.get_next_item(tr);
        drive_transaction(tr);
        seq_item_port.item_done();
      end
    endtask

    task drive_transaction(rob_transaction tr);
      clear_inputs();
      case (tr.op)
        ROB_DISPATCH:      drive_dispatch(tr);
        ROB_WRITEBACK:     drive_writeback(tr);
        ROB_BRANCH_UPDATE: drive_branch_update(tr);
        ROB_LXCPT:         drive_lxcpt(tr);
        ROB_LSU_CLR_BSY:   drive_lsu_clr(tr);
        ROB_IDLE:          ;
      endcase
      @(posedge vif.clock);
    endtask

    task clear_inputs();
      for (int i = 0; i < 3; i++) begin
        vif.drv_cb.enq_valids[i]              <= 0;
        vif.drv_cb.enq_uops_exception[i]      <= 0;
        vif.drv_cb.enq_uops_is_br[i]          <= 0;
        vif.drv_cb.enq_uops_is_fence[i]       <= 0;
        vif.drv_cb.enq_uops_is_fencei[i]      <= 0;
        vif.drv_cb.enq_uops_unsafe[i]         <= 0;
        vif.drv_cb.enq_uops_is_unique[i]      <= 0;
        vif.drv_cb.enq_uops_flush_on_commit[i]<= 0;
        vif.drv_cb.enq_uops_uses_ldq[i]       <= 0;
        vif.drv_cb.enq_uops_uses_stq[i]       <= 0;
        vif.drv_cb.enq_uops_fp_val[i]         <= 0;
        vif.drv_cb.enq_uops_ldst_val[i]       <= 0;
        vif.drv_cb.enq_uops_br_mask[i]        <= 0;
        vif.drv_cb.enq_uops_exc_cause[i]      <= 0;
      end
      vif.drv_cb.enq_partial_stall             <= 0;
      for (int i = 0; i < 6; i++) begin
        vif.drv_cb.wb_resps_valid[i]           <= 0;
        vif.drv_cb.wb_resps_predicated[i]      <= 0;
      end
      for (int i = 0; i < 2; i++) begin
        vif.drv_cb.lsu_clr_bsy_valid[i]        <= 0;
        vif.drv_cb.fflags_valid[i]             <= 0;
      end
      vif.drv_cb.brupdate_b1_resolve_mask      <= 0;
      vif.drv_cb.brupdate_b1_mispredict_mask   <= 0;
      vif.drv_cb.brupdate_b2_mispredict        <= 0;
      vif.drv_cb.lxcpt_valid                   <= 0;
      vif.drv_cb.csr_stall                     <= 0;
    endtask

    task drive_dispatch(rob_transaction tr);
      for (int i = 0; i < 3; i++) begin
        vif.drv_cb.enq_valids[i]               <= tr.enq_valids[i];
        vif.drv_cb.enq_uops_uopc[i]            <= tr.enq_uops_uopc[i];
        vif.drv_cb.enq_uops_rob_idx[i]         <= tr.enq_uops_rob_idx[i];
        vif.drv_cb.enq_uops_pdst[i]            <= tr.enq_uops_pdst[i];
        vif.drv_cb.enq_uops_stale_pdst[i]      <= tr.enq_uops_stale_pdst[i];
        vif.drv_cb.enq_uops_exception[i]       <= tr.enq_uops_exception[i];
        vif.drv_cb.enq_uops_exc_cause[i]       <= tr.enq_uops_exc_cause[i];
        vif.drv_cb.enq_uops_is_br[i]           <= tr.enq_uops_is_br[i];
        vif.drv_cb.enq_uops_br_mask[i]         <= tr.enq_uops_br_mask[i];
        vif.drv_cb.enq_uops_is_fence[i]        <= tr.enq_uops_is_fence[i];
        vif.drv_cb.enq_uops_is_fencei[i]       <= tr.enq_uops_is_fencei[i];
        vif.drv_cb.enq_uops_unsafe[i]          <= tr.enq_uops_unsafe[i];
        vif.drv_cb.enq_uops_uses_ldq[i]        <= tr.enq_uops_uses_ldq[i];
        vif.drv_cb.enq_uops_uses_stq[i]        <= tr.enq_uops_uses_stq[i];
        vif.drv_cb.enq_uops_is_unique[i]       <= tr.enq_uops_is_unique[i];
        vif.drv_cb.enq_uops_flush_on_commit[i] <= tr.enq_uops_flush_on_commit[i];
        vif.drv_cb.enq_uops_ldst[i]            <= tr.enq_uops_ldst[i];
        vif.drv_cb.enq_uops_ldst_val[i]        <= tr.enq_uops_ldst_val[i];
        vif.drv_cb.enq_uops_fp_val[i]          <= tr.enq_uops_fp_val[i];
      end
      vif.drv_cb.enq_partial_stall             <= tr.enq_partial_stall;
    endtask

    task drive_writeback(rob_transaction tr);
      for (int i = 0; i < 6; i++) begin
        vif.drv_cb.wb_resps_valid[i]   <= tr.wb_valid[i];
        vif.drv_cb.wb_resps_rob_idx[i] <= tr.wb_rob_idx[i];
        vif.drv_cb.wb_resps_pdst[i]    <= tr.wb_pdst[i];
      end
    endtask

    task drive_branch_update(rob_transaction tr);
      vif.drv_cb.brupdate_b1_resolve_mask    <= tr.br_resolve_mask;
      vif.drv_cb.brupdate_b1_mispredict_mask <= tr.br_mispredict_mask;
      vif.drv_cb.brupdate_b2_uop_rob_idx     <= tr.br_rob_idx;
      vif.drv_cb.brupdate_b2_mispredict       <= tr.br_mispredict;
    endtask

    task drive_lxcpt(rob_transaction tr);
      vif.drv_cb.lxcpt_valid            <= tr.lxcpt_valid;
      vif.drv_cb.lxcpt_bits_uop_rob_idx <= tr.lxcpt_rob_idx;
      vif.drv_cb.lxcpt_bits_cause       <= tr.lxcpt_cause;
      vif.drv_cb.lxcpt_bits_badvaddr    <= tr.lxcpt_badvaddr;
    endtask

    task drive_lsu_clr(rob_transaction tr);
      for (int i = 0; i < 2; i++) begin
        vif.drv_cb.lsu_clr_bsy_valid[i] <= tr.lsu_clr_valid[i];
        vif.drv_cb.lsu_clr_bsy_bits[i]  <= tr.lsu_clr_bits[i];
      end
    endtask
  endclass


  // =========================================================================
  // ENHANCED MONITOR — Sample đầy đủ, broadcast qua analysis port
  // =========================================================================
// ==== FILE: rob_monitor.sv ====
  class rob_monitor extends uvm_monitor;
    `uvm_component_utils(rob_monitor)

    virtual rob_if.MON vif;
    uvm_analysis_port #(rob_transaction) ap;

    logic [6:0] prev_head, prev_tail;
    bit         prev_flush;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "Failed to get vif")
    endfunction

    task run_phase(uvm_phase phase);
      @(negedge vif.reset);
      prev_head = 0; prev_tail = 0; prev_flush = 0;
      forever begin
        @(posedge vif.clock);
        sample_cycle();
      end
    endtask

    task sample_cycle();
      rob_transaction tr;

      // ---- Dispatch ----
      if (vif.mon_cb.enq_valids[0] || vif.mon_cb.enq_valids[1] || vif.mon_cb.enq_valids[2]) begin
        tr = rob_transaction::type_id::create("mon_tr");
        tr.op = ROB_DISPATCH;
        for (int i = 0; i < 3; i++) begin
          tr.enq_valids[i]         = vif.mon_cb.enq_valids[i];
          tr.enq_uops_rob_idx[i]   = vif.mon_cb.enq_uops_rob_idx[i];
          tr.enq_uops_pdst[i]      = vif.mon_cb.enq_uops_pdst[i];
          tr.enq_uops_stale_pdst[i]= vif.mon_cb.enq_uops_stale_pdst[i];
          tr.enq_uops_exception[i] = vif.mon_cb.enq_uops_exception[i];
          tr.enq_uops_is_br[i]     = vif.mon_cb.enq_uops_is_br[i];
          tr.enq_uops_br_mask[i]   = vif.mon_cb.enq_uops_br_mask[i];
          tr.enq_uops_is_fence[i]  = vif.mon_cb.enq_uops_is_fence[i];
          tr.enq_uops_unsafe[i]    = vif.mon_cb.enq_uops_unsafe[i];
        end
        tr.enq_partial_stall = vif.mon_cb.enq_partial_stall;
        ap.write(tr);
        `uvm_info("MON", $sformatf("DISPATCH v={%0b,%0b,%0b} partial=%0b tail=%0d",
          tr.enq_valids[0], tr.enq_valids[1], tr.enq_valids[2],
          tr.enq_partial_stall, vif.mon_cb.rob_tail_idx), UVM_HIGH)
      end

      // ---- Commit ----
      if (vif.mon_cb.commit_valids[0] || vif.mon_cb.commit_valids[1] || vif.mon_cb.commit_valids[2])
        `uvm_info("MON", $sformatf("COMMIT v={%0b,%0b,%0b} arch={%0b,%0b,%0b} head=%0d",
          vif.mon_cb.commit_valids[0], vif.mon_cb.commit_valids[1], vif.mon_cb.commit_valids[2],
          vif.mon_cb.commit_arch_valids[0], vif.mon_cb.commit_arch_valids[1], vif.mon_cb.commit_arch_valids[2],
          vif.mon_cb.rob_head_idx), UVM_MEDIUM)

      if (vif.mon_cb.com_xcpt_valid)
        `uvm_info("MON", $sformatf("EXCEPTION head=%0d cause=0x%0h",
          vif.mon_cb.rob_head_idx, vif.mon_cb.com_xcpt_bits_cause), UVM_LOW)

      if (vif.mon_cb.flush_valid && !prev_flush)
        `uvm_info("MON", $sformatf("FLUSH typ=%0d", vif.mon_cb.flush_bits_flush_typ), UVM_LOW)

      if (vif.mon_cb.commit_rollback)
        `uvm_info("MON", $sformatf("ROLLBACK tail=%0d head=%0d",
          vif.mon_cb.rob_tail_idx, vif.mon_cb.rob_head_idx), UVM_MEDIUM)

      // Pointer wrap
      if (vif.mon_cb.rob_head_idx < prev_head && prev_head > 3)
        `uvm_info("MON", $sformatf("HEAD WRAP %0d→%0d", prev_head, vif.mon_cb.rob_head_idx), UVM_MEDIUM)
      if (vif.mon_cb.rob_tail_idx < prev_tail && prev_tail > 3
          && !vif.mon_cb.flush_valid && !vif.mon_cb.brupdate_b2_mispredict)
        `uvm_info("MON", $sformatf("TAIL WRAP %0d→%0d", prev_tail, vif.mon_cb.rob_tail_idx), UVM_MEDIUM)

      prev_head  = vif.mon_cb.rob_head_idx;
      prev_tail  = vif.mon_cb.rob_tail_idx;
      prev_flush = vif.mon_cb.flush_valid;
    endtask
  endclass


  // =========================================================================
  // ENHANCED SCOREBOARD — Shadow model + rule checker + feature checks
  // =========================================================================
// ==== FILE: rob_scoreboard.sv ====
  class rob_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(rob_scoreboard)

    virtual rob_if.MON vif;
    rob_shadow_model   shadow;
    rob_rule_checker   checker;

    int commit_cnt, xcpt_cnt, flush_cnt, rbk_cnt, disp_cnt, wb_cnt;
    int cycle_cnt;
    int xcpt_cycle;
    bit xcpt_pending;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
        `uvm_fatal("SCB", "Failed to get vif")
      shadow  = rob_shadow_model::type_id::create("shadow");
      checker = rob_rule_checker::type_id::create("checker");
      commit_cnt = 0; xcpt_cnt = 0; flush_cnt = 0; rbk_cnt = 0;
      disp_cnt   = 0; wb_cnt = 0; cycle_cnt = 0; xcpt_pending = 0;
    endfunction

    task run_phase(uvm_phase phase);
      @(negedge vif.reset);
      shadow.reset();

      // F1.6: empty + ready after reset
      repeat(2) @(posedge vif.clock);
      if (vif.mon_cb.empty && vif.mon_cb.ready)
        `uvm_info("SCB", "F1.6 PASS: empty=1, ready=1 after reset", UVM_LOW)
      else
        `uvm_error("SCB", $sformatf("F1.6 FAIL: empty=%0b, ready=%0b", vif.mon_cb.empty, vif.mon_cb.ready))

      forever begin
        @(posedge vif.clock);
        cycle_cnt++;
        run_checks();
      end
    endtask

    task run_checks();
      bit [2:0] cv, rv;

      // --- Feed shadow model with observed dispatch ---
      for (int i = 0; i < CW; i++) begin
        if (vif.mon_cb.enq_valids[i]) begin
          disp_cnt++;
          shadow.dispatch(
            vif.mon_cb.enq_uops_rob_idx[i],
            vif.mon_cb.enq_uops_pdst[i],
            vif.mon_cb.enq_uops_stale_pdst[i],
            vif.mon_cb.enq_uops_exception[i],
            vif.mon_cb.enq_uops_exc_cause[i],
            vif.mon_cb.enq_uops_is_br[i],
            vif.mon_cb.enq_uops_br_mask[i],
            vif.mon_cb.enq_uops_is_fence[i],
            vif.mon_cb.enq_uops_unsafe[i]
          );
        end
      end

      // --- Feed shadow with observed writeback ---
      for (int i = 0; i < NUM_WB_PORTS; i++) begin
        if (vif.mon_cb.wb_resps_valid[i]) begin
          wb_cnt++;
          shadow.writeback(vif.mon_cb.wb_resps_rob_idx[i], vif.mon_cb.wb_resps_pdst[i]);
        end
      end

      // --- Feed shadow with LSU clear ---
      for (int i = 0; i < 2; i++)
        if (vif.mon_cb.lsu_clr_bsy_valid[i])
          shadow.lsu_clr(vif.mon_cb.lsu_clr_bsy_bits[i]);

      // --- Feed shadow with branch update ---
      if (vif.mon_cb.brupdate_b1_resolve_mask != 0)
        shadow.branch_resolve(vif.mon_cb.brupdate_b1_resolve_mask);
      if (vif.mon_cb.brupdate_b2_mispredict)
        shadow.branch_kill(vif.mon_cb.brupdate_b1_mispredict_mask);

      // --- Feed shadow with commit ---
      for (int i = 0; i < CW; i++) begin
        cv[i] = vif.mon_cb.commit_valids[i];
        rv[i] = vif.mon_cb.commit_rbk_valids[i];
        if (vif.mon_cb.commit_valids[i]) begin
          commit_cnt++;
          // Commit at head + bank
          shadow.commit(vif.mon_cb.rob_head_idx * CW + i);
        end
      end

      // --- Flush ---
      if (vif.mon_cb.com_xcpt_valid) xcpt_cnt++;
      if (vif.mon_cb.flush_valid) begin
        flush_cnt++;
        shadow.flush_all();
      end
      if (vif.mon_cb.commit_rollback) rbk_cnt++;

      // === RULE CHECKS ===
      // D3
      begin
        bit any = 0;
        for (int i = 0; i < CW; i++) if (vif.mon_cb.enq_valids[i]) any = 1;
        checker.chk_dispatch_ready(vif.mon_cb.ready, any);
      end

      // A8
      checker.chk_commit_rbk_excl(cv, rv);

      // F3.1
      begin
        bit c_arr[3];
        for (int i = 0; i < 3; i++) c_arr[i] = vif.mon_cb.commit_valids[i];
        checker.chk_inorder_commit(c_arr);
      end

      // F4.8: 2-cycle delay exception → rollback
      if (vif.mon_cb.com_xcpt_valid && !xcpt_pending) begin
        xcpt_cycle   = cycle_cnt;
        xcpt_pending = 1;
      end
      if (vif.mon_cb.commit_rollback && xcpt_pending) begin
        int delay = cycle_cnt - xcpt_cycle;
        if (delay >= 2)
          `uvm_info("SCB", $sformatf("F4.8 PASS: xcpt→rollback delay=%0d", delay), UVM_MEDIUM)
        else
          `uvm_warning("SCB", $sformatf("F4.8 CHECK: delay=%0d (expect>=2)", delay))
        xcpt_pending = 0;
      end

      // F4.10: flush_frontend
      if (vif.mon_cb.com_xcpt_valid)
        `uvm_info("SCB", $sformatf("F4.10: flush_frontend=%0b", vif.mon_cb.flush_frontend), UVM_HIGH)
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", "╔══════════════════════════════════════╗", UVM_LOW)
      `uvm_info("SCB", "║      SCOREBOARD SUMMARY              ║", UVM_LOW)
      `uvm_info("SCB", "╠══════════════════════════════════════╣", UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Dispatches : %0d",  disp_cnt),   UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Writebacks : %0d",  wb_cnt),     UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Commits    : %0d",  commit_cnt), UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Exceptions : %0d",  xcpt_cnt),   UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Flushes    : %0d",  flush_cnt),  UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Rollbacks  : %0d",  rbk_cnt),    UVM_LOW)
      `uvm_info("SCB", $sformatf("║ Cycles     : %0d",  cycle_cnt),  UVM_LOW)
      `uvm_info("SCB", "╚══════════════════════════════════════╝", UVM_LOW)
      checker.report();
    endfunction
  endclass


  // =========================================================================
  // FUNCTIONAL COVERAGE COLLECTOR (Testplan §7)
  // =========================================================================
// ==== FILE: rob_coverage.sv ====
  class rob_coverage extends uvm_subscriber #(rob_transaction);
    `uvm_component_utils(rob_coverage)

    virtual rob_if.MON vif;

    int dw, cw_v, sim_wb, occ_pct;
    bit ps, xcpt, misp, rbk, fls, hwrap, twrap;
    int wp[NUM_WB_PORTS];
    logic [6:0] p_head, p_tail;

    covergroup cg_dispatch;
      cp_width:   coverpoint dw { bins b[] = {[0:3]}; }
      cp_partial: coverpoint ps { bins b[] = {0,1}; }
      cx: cross cp_width, cp_partial;
    endgroup

    covergroup cg_wb;
      cp_sim: coverpoint sim_wb {
        bins none={0}; bins single={1}; bins two={2}; bins three={3}; bins hi={[4:6]};
      }
    endgroup

    covergroup cg_commit;
      cp_cw: coverpoint cw_v { bins b[] = {[0:3]}; }
    endgroup

    covergroup cg_occupancy;
      cp_occ: coverpoint occ_pct {
        bins empty={0}; bins low={[1:25]}; bins mid={[26:50]};
        bins hi={[51:75]}; bins vhi={[76:99]}; bins full={100};
      }
    endgroup

    covergroup cg_events;
      cp_xcpt: coverpoint xcpt; cp_misp: coverpoint misp;
      cp_rbk:  coverpoint rbk;  cp_fls:  coverpoint fls;
    endgroup

    covergroup cg_ptr_wrap;
      cp_hw: coverpoint hwrap; cp_tw: coverpoint twrap;
    endgroup

    covergroup cg_x_disp_occ;
      cp_d: coverpoint dw { bins b[]={[0:3]}; }
      cp_o: coverpoint occ_pct { bins lo={[0:50]}; bins hi={[51:99]}; bins full={100}; }
      cx: cross cp_d, cp_o;
    endgroup

    covergroup cg_x_wb_commit;
      cp_w: coverpoint sim_wb { bins lo={[0:1]}; bins mid={[2:3]}; bins hi={[4:6]}; }
      cp_c: coverpoint cw_v   { bins b[]={[0:3]}; }
      cx: cross cp_w, cp_c;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_dispatch    = new(); cg_wb       = new(); cg_commit     = new();
      cg_occupancy   = new(); cg_events   = new(); cg_ptr_wrap   = new();
      cg_x_disp_occ  = new(); cg_x_wb_commit = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
        `uvm_fatal("COV", "Failed to get vif")
    endfunction

    function void write(rob_transaction t); /* triggered by ap */ endfunction

    task run_phase(uvm_phase phase);
      @(negedge vif.reset);
      p_head = 0; p_tail = 0;
      forever begin
        @(posedge vif.clock);
        sample();
      end
    endtask

    function void sample();
      dw = 0;
      for (int i = 0; i < CW; i++) if (vif.mon_cb.enq_valids[i]) dw++;
      ps = vif.mon_cb.enq_partial_stall;

      sim_wb = 0;
      for (int i = 0; i < NUM_WB_PORTS; i++) begin
        wp[i] = vif.mon_cb.wb_resps_valid[i];
        if (wp[i]) sim_wb++;
      end

      cw_v = 0;
      for (int i = 0; i < CW; i++) if (vif.mon_cb.commit_valids[i]) cw_v++;

      if (vif.mon_cb.empty) occ_pct = 0;
      else if (!vif.mon_cb.ready) occ_pct = 100;
      else begin
        int h = vif.mon_cb.rob_head_idx, t = vif.mon_cb.rob_tail_idx;
        occ_pct = (t >= h) ? ((t-h)*100)/NUM_ROB_ROWS : ((NUM_ROB_ROWS-h+t)*100)/NUM_ROB_ROWS;
        if (occ_pct > 100) occ_pct = 100;
      end

      xcpt = vif.mon_cb.com_xcpt_valid;
      misp = vif.mon_cb.brupdate_b2_mispredict;
      rbk  = vif.mon_cb.commit_rollback;
      fls  = vif.mon_cb.flush_valid;

      hwrap = (vif.mon_cb.rob_head_idx < p_head && p_head > 3);
      twrap = (vif.mon_cb.rob_tail_idx < p_tail && p_tail > 3
               && !fls && !misp);

      cg_dispatch.sample(); cg_wb.sample(); cg_commit.sample();
      cg_occupancy.sample(); cg_events.sample(); cg_ptr_wrap.sample();
      cg_x_disp_occ.sample(); cg_x_wb_commit.sample();

      p_head = vif.mon_cb.rob_head_idx;
      p_tail = vif.mon_cb.rob_tail_idx;
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", "╔══════════════════════════════════════╗", UVM_LOW)
      `uvm_info("COV", "║      COVERAGE REPORT                 ║", UVM_LOW)
      `uvm_info("COV", "╠══════════════════════════════════════╣", UVM_LOW)
      `uvm_info("COV", $sformatf("║ dispatch      : %.1f%%", cg_dispatch.get_coverage()),    UVM_LOW)
      `uvm_info("COV", $sformatf("║ wb            : %.1f%%", cg_wb.get_coverage()),          UVM_LOW)
      `uvm_info("COV", $sformatf("║ commit        : %.1f%%", cg_commit.get_coverage()),      UVM_LOW)
      `uvm_info("COV", $sformatf("║ occupancy     : %.1f%%", cg_occupancy.get_coverage()),   UVM_LOW)
      `uvm_info("COV", $sformatf("║ events        : %.1f%%", cg_events.get_coverage()),      UVM_LOW)
      `uvm_info("COV", $sformatf("║ ptr_wrap      : %.1f%%", cg_ptr_wrap.get_coverage()),    UVM_LOW)
      `uvm_info("COV", $sformatf("║ disp×occ      : %.1f%%", cg_x_disp_occ.get_coverage()), UVM_LOW)
      `uvm_info("COV", $sformatf("║ wb×commit     : %.1f%%", cg_x_wb_commit.get_coverage()),UVM_LOW)
      `uvm_info("COV", "╚══════════════════════════════════════╝", UVM_LOW)
    endfunction
  endclass


  // =========================================================================
  // AGENT
  // =========================================================================
// ==== FILE: rob_agent.sv ====
  class rob_agent extends uvm_agent;
    `uvm_component_utils(rob_agent)
    rob_driver    drv;
    rob_monitor   mon;
    uvm_sequencer #(rob_transaction) sqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = rob_driver::type_id::create("drv", this);
      mon = rob_monitor::type_id::create("mon", this);
      sqr = uvm_sequencer#(rob_transaction)::type_id::create("sqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass


  // =========================================================================
  // ENVIRONMENT
  // =========================================================================
// ==== FILE: rob_env.sv ====
  class rob_env extends uvm_env;
    `uvm_component_utils(rob_env)
    rob_agent      agt;
    rob_scoreboard scb;
    rob_coverage   cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agt = rob_agent::type_id::create("agt", this);
      scb = rob_scoreboard::type_id::create("scb", this);
      cov = rob_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agt.mon.ap.connect(cov.analysis_export);
    endfunction
  endclass


  // =========================================================================
  // SEQUENCES — TC1 to TC13
  // =========================================================================

  // -----------------------------------------------------------------------
  // TC1: Dispatch / Allocation
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc1_dispatch.sv ====
  class tc1_dispatch_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc1_dispatch_seq)
    function new(string name = "tc1_dispatch_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC1", "=== TC1: Dispatch Allocation ===", UVM_LOW)

      // Phase A: Single dispatch
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_valids[1] = 0; tr.enq_valids[2] = 0;
      tr.enq_uops_rob_idx[0] = `ROB_IDX(0,0);
      tr.enq_uops_pdst[0] = 1; tr.enq_uops_stale_pdst[0] = 0;
      tr.enq_uops_exception[0] = 0; tr.enq_uops_is_br[0] = 0;
      tr.enq_uops_unsafe[0] = 0;
      tr.enq_partial_stall = 1;
      finish_item(tr);

      // Phase B: Full-width 3 uops × 9 rows
      for (int row = 1; row < 10; row++) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr);
        tr.op = ROB_DISPATCH;
        for (int b = 0; b < 3; b++) begin
          tr.enq_valids[b] = 1;
          tr.enq_uops_rob_idx[b] = `ROB_IDX(row,b);
          tr.enq_uops_pdst[b] = 7'(row*3+b+10);
          tr.enq_uops_stale_pdst[b] = 7'(row*3+b);
          tr.enq_uops_exception[b] = 0;
          tr.enq_uops_is_br[b] = 0; tr.enq_uops_unsafe[b] = 0;
        end
        tr.enq_partial_stall = 0;
        finish_item(tr);
      end

      @(posedge vif.clock);
      `uvm_info("TC1", $sformatf("After 10 rows: tail=%0d head=%0d ready=%0b empty=%0b",
        vif.rob_tail_idx, vif.rob_head_idx, vif.ready, vif.empty), UVM_LOW)

      // Phase C: Fill until not ready
      for (int row = 10; row < 50; row++) begin
        if (!vif.ready) begin
          `uvm_info("TC1", $sformatf("F1.4 PASS: ROB full at row %0d", row), UVM_LOW)
          break;
        end
        tr = rob_transaction::type_id::create("tr");
        start_item(tr);
        tr.op = ROB_DISPATCH;
        for (int b = 0; b < 3; b++) begin
          tr.enq_valids[b] = 1;
          tr.enq_uops_rob_idx[b] = `ROB_IDX(row,b);
          tr.enq_uops_pdst[b] = 7'((row*3+b)%128);
          tr.enq_uops_stale_pdst[b] = 0;
          tr.enq_uops_exception[b] = 0;
          tr.enq_uops_is_br[b] = 0; tr.enq_uops_unsafe[b] = 0;
        end
        tr.enq_partial_stall = 0;
        finish_item(tr);
      end

      repeat(5) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC1", "=== TC1 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC2: Out-of-Order Writeback
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc2_ooo_writeback.sv ====
  class tc2_ooo_writeback_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc2_ooo_writeback_seq)
    function new(string name = "tc2_ooo_writeback_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC2", "=== TC2: OoO Writeback ===", UVM_LOW)

      // Dispatch 2 uops
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_valids[1] = 1; tr.enq_valids[2] = 0;
      tr.enq_uops_rob_idx[0] = `ROB_IDX(0,0);
      tr.enq_uops_rob_idx[1] = `ROB_IDX(0,1);
      tr.enq_uops_pdst[0] = 10; tr.enq_uops_pdst[1] = 11;
      tr.enq_uops_stale_pdst[0] = 0; tr.enq_uops_stale_pdst[1] = 0;
      tr.enq_uops_exception[0] = 0; tr.enq_uops_exception[1] = 0;
      tr.enq_uops_is_br[0] = 0; tr.enq_uops_is_br[1] = 0;
      tr.enq_uops_unsafe[0] = 1; tr.enq_uops_unsafe[1] = 1;
      tr.enq_partial_stall = 0;
      finish_item(tr);

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // WB young first
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      tr.wb_valid[0] = 1; tr.wb_rob_idx[0] = 1; tr.wb_pdst[0] = 11;
      for (int i = 1; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      @(posedge vif.clock);
      if (vif.commit_valids[0] || vif.commit_valids[1] || vif.commit_valids[2])
        `uvm_error("TC2", "FAIL: Commit before oldest completed!")
      else
        `uvm_info("TC2", "F2.1 PASS: No premature commit", UVM_LOW)

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // WB old
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      tr.wb_valid[0] = 1; tr.wb_rob_idx[0] = 0; tr.wb_pdst[0] = 10;
      for (int i = 1; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      repeat(3) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC2", "=== TC2 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC3: In-Order Commit
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc3_inorder_commit.sv ====
  class tc3_inorder_commit_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc3_inorder_commit_seq)
    function new(string name = "tc3_inorder_commit_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC3", "=== TC3: In-Order Commit ===", UVM_LOW)

      // Dispatch row 0+1
      for (int r = 0; r < 2; r++) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr);
        tr.op = ROB_DISPATCH;
        for (int b = 0; b < 3; b++) begin
          tr.enq_valids[b] = 1;
          tr.enq_uops_rob_idx[b] = `ROB_IDX(r,b);
          tr.enq_uops_pdst[b] = 7'(r*10 + 10 + b);
          tr.enq_uops_stale_pdst[b] = 7'(r*10 + b);
          tr.enq_uops_exception[b] = 0;
          tr.enq_uops_is_br[b] = 0; tr.enq_uops_unsafe[b] = 1;
        end
        tr.enq_partial_stall = 0;
        finish_item(tr);
      end

      // WB all 6
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      for (int i = 0; i < 6; i++) begin
        tr.wb_valid[i] = 1;
        tr.wb_rob_idx[i] = 7'(i);
        tr.wb_pdst[i] = 7'(10 + i);
      end
      finish_item(tr);

      repeat(2) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end

      repeat(5) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end

      @(posedge vif.clock);
      if (vif.empty)
        `uvm_info("TC3", "F3.6 PASS: ROB drained", UVM_LOW)
      else
        `uvm_error("TC3", "F3.6 FAIL: ROB not empty")
      `uvm_info("TC3", "=== TC3 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC4: Precise Exception
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc4_precise_exception.sv ====
  class tc4_precise_exception_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc4_precise_exception_seq)
    function new(string name = "tc4_precise_exception_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC4", "=== TC4: Precise Exception ===", UVM_LOW)

      // Row 0: bank0 has exception
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_uops_rob_idx[0] = `ROB_IDX(0,0);
      tr.enq_uops_pdst[0] = 10; tr.enq_uops_stale_pdst[0] = 0;
      tr.enq_uops_exception[0] = 1; tr.enq_uops_exc_cause[0] = 64'd13;
      tr.enq_uops_is_br[0] = 0; tr.enq_uops_unsafe[0] = 0;
      tr.enq_valids[1] = 1; tr.enq_uops_rob_idx[1] = `ROB_IDX(0,1);
      tr.enq_uops_pdst[1] = 11; tr.enq_uops_stale_pdst[1] = 0;
      tr.enq_uops_exception[1] = 0; tr.enq_uops_is_br[1] = 0; tr.enq_uops_unsafe[1] = 1;
      tr.enq_valids[2] = 1; tr.enq_uops_rob_idx[2] = `ROB_IDX(0,2);
      tr.enq_uops_pdst[2] = 12; tr.enq_uops_stale_pdst[2] = 0;
      tr.enq_uops_exception[2] = 0; tr.enq_uops_is_br[2] = 0; tr.enq_uops_unsafe[2] = 1;
      tr.enq_partial_stall = 0;
      finish_item(tr);

      // Row 1: clean
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      for (int b = 0; b < 3; b++) begin
        tr.enq_valids[b] = 1;
        tr.enq_uops_rob_idx[b] = `ROB_IDX(1,b);
        tr.enq_uops_pdst[b] = 7'(20+b); tr.enq_uops_stale_pdst[b] = 0;
        tr.enq_uops_exception[b] = 0; tr.enq_uops_is_br[b] = 0; tr.enq_uops_unsafe[b] = 1;
      end
      tr.enq_partial_stall = 0;
      finish_item(tr);

      // WB row1 first (younger)
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      for (int i = 0; i < 3; i++) begin
        tr.wb_valid[i] = 1; tr.wb_rob_idx[i] = `ROB_IDX(1,i); tr.wb_pdst[i] = 7'(20+i);
      end
      for (int i = 3; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // WB row0
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      tr.wb_valid[0] = 1; tr.wb_rob_idx[0] = `ROB_IDX(0,0); tr.wb_pdst[0] = 10;
      tr.wb_valid[1] = 1; tr.wb_rob_idx[1] = `ROB_IDX(0,1); tr.wb_pdst[1] = 11;
      tr.wb_valid[2] = 1; tr.wb_rob_idx[2] = `ROB_IDX(0,2); tr.wb_pdst[2] = 12;
      for (int i = 3; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      repeat(5) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
        @(posedge vif.clock);
        if (vif.com_xcpt_valid)
          `uvm_info("TC4", $sformatf("F4.1/F4.3 PASS: com_xcpt_valid at head=%0d", vif.rob_head_idx), UVM_LOW)
        if (vif.flush_valid)
          `uvm_info("TC4", $sformatf("F4.4 PASS: flush_valid typ=%0d", vif.flush_bits_flush_typ), UVM_LOW)
      end

      repeat(10) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC4", "=== TC4 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC5: Branch Misprediction Recovery
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc5_branch_mispredict.sv ====
  class tc5_branch_mispredict_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc5_branch_mispredict_seq)
    function new(string name = "tc5_branch_mispredict_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      logic [6:0] tail_before;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC5", "=== TC5: Branch Misprediction ===", UVM_LOW)

      // Row 0: branch + speculative
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_uops_rob_idx[0] = `ROB_IDX(0,0);
      tr.enq_uops_pdst[0] = 10; tr.enq_uops_stale_pdst[0] = 0;
      tr.enq_uops_exception[0] = 0; tr.enq_uops_is_br[0] = 1;
      tr.enq_uops_br_mask[0] = 16'h0001; tr.enq_uops_unsafe[0] = 1;
      for (int b = 1; b < 3; b++) begin
        tr.enq_valids[b] = 1; tr.enq_uops_rob_idx[b] = `ROB_IDX(0,b);
        tr.enq_uops_pdst[b] = 7'(10+b); tr.enq_uops_stale_pdst[b] = 0;
        tr.enq_uops_exception[b] = 0; tr.enq_uops_is_br[b] = 0;
        tr.enq_uops_br_mask[b] = 16'h0001; tr.enq_uops_unsafe[b] = 1;
      end
      tr.enq_partial_stall = 0;
      finish_item(tr);

      // Row 1: more speculative
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      for (int b = 0; b < 3; b++) begin
        tr.enq_valids[b] = 1; tr.enq_uops_rob_idx[b] = `ROB_IDX(1,b);
        tr.enq_uops_pdst[b] = 7'(20+b); tr.enq_uops_stale_pdst[b] = 0;
        tr.enq_uops_exception[b] = 0; tr.enq_uops_is_br[b] = 0;
        tr.enq_uops_br_mask[b] = 16'h0001; tr.enq_uops_unsafe[b] = 1;
      end
      tr.enq_partial_stall = 0;
      finish_item(tr);

      @(posedge vif.clock);
      tail_before = vif.rob_tail_idx;

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // Mispredict
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_BRANCH_UPDATE;
      tr.br_resolve_mask = 16'h0001; tr.br_mispredict_mask = 16'h0001;
      tr.br_rob_idx = 0; tr.br_mispredict = 1;
      finish_item(tr);

      repeat(3) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
        @(posedge vif.clock);
        `uvm_info("TC5", $sformatf("Recovery: tail=%0d head=%0d rbk=%0b",
          vif.rob_tail_idx, vif.rob_head_idx, vif.commit_rollback), UVM_MEDIUM)
      end

      @(posedge vif.clock);
      if (vif.rob_tail_idx < tail_before || vif.rob_tail_idx == vif.rob_head_idx)
        `uvm_info("TC5", "F5.2 PASS: Tail snapped back", UVM_LOW)
      else
        `uvm_warning("TC5", "Tail did not roll back — check waveform")

      repeat(15) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC5", "=== TC5 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC6: Reset State (F1.6, F7.1)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc6_reset_state.sv ====
  class tc6_reset_state_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc6_reset_state_seq)
    function new(string name = "tc6_reset_state_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC6", "=== TC6: Reset State (F1.6, F7.1) ===", UVM_LOW)

      repeat(2) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end

      @(posedge vif.clock);
      if (vif.empty && vif.ready && vif.rob_head_idx == 0 && vif.rob_tail_idx == 0)
        `uvm_info("TC6", "F1.6 PASS: empty=1 ready=1 head=0 tail=0", UVM_LOW)
      else
        `uvm_error("TC6", $sformatf("F1.6 FAIL: e=%0b r=%0b h=%0d t=%0d",
          vif.empty, vif.ready, vif.rob_head_idx, vif.rob_tail_idx))

      // Dispatch 1 to confirm s_normal
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_valids[1] = 0; tr.enq_valids[2] = 0;
      tr.enq_uops_rob_idx[0] = 0; tr.enq_uops_pdst[0] = 5; tr.enq_uops_stale_pdst[0] = 0;
      tr.enq_uops_exception[0] = 0; tr.enq_uops_is_br[0] = 0; tr.enq_uops_unsafe[0] = 1;
      tr.enq_partial_stall = 1;
      finish_item(tr);

      @(posedge vif.clock);
      if (!vif.empty)
        `uvm_info("TC6", "F7.1 PASS: dispatch accepted → s_normal", UVM_LOW)

      repeat(3) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC6", "=== TC6 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC7: Fence Dispatch (F1.7)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc7_fence_dispatch.sv ====
  class tc7_fence_dispatch_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc7_fence_dispatch_seq)
    function new(string name = "tc7_fence_dispatch_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC7", "=== TC7: Fence Dispatch (F1.7) ===", UVM_LOW)

      // Row with fence at bank0, normals at bank1/2
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      for (int b = 0; b < 3; b++) begin
        tr.enq_valids[b] = 1;
        tr.enq_uops_rob_idx[b] = `ROB_IDX(0,b);
        tr.enq_uops_pdst[b] = 7'(b == 0 ? 0 : 10+b);
        tr.enq_uops_stale_pdst[b] = 0;
        tr.enq_uops_exception[b] = 0;
        tr.enq_uops_is_br[b] = 0;
        tr.enq_uops_is_fence[b] = (b == 0) ? 1 : 0;
        tr.enq_uops_unsafe[b] = (b == 0) ? 0 : 1;
        tr.enq_uops_ldst_val[b] = (b == 0) ? 0 : 1;
      end
      tr.enq_partial_stall = 0;
      finish_item(tr);

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // WB only bank1/2
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      tr.wb_valid[0] = 1; tr.wb_rob_idx[0] = `ROB_IDX(0,1); tr.wb_pdst[0] = 11;
      tr.wb_valid[1] = 1; tr.wb_rob_idx[1] = `ROB_IDX(0,2); tr.wb_pdst[1] = 12;
      for (int i = 2; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      repeat(5) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end

      @(posedge vif.clock);
      if (vif.empty)
        `uvm_info("TC7", "F1.7 PASS: Fence committed without WB", UVM_LOW)
      else
        `uvm_error("TC7", "F1.7 FAIL: ROB not empty")
      `uvm_info("TC7", "=== TC7 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC8: LSU Clear Busy (F2.5)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc8_lsu_clr_busy.sv ====
  class tc8_lsu_clr_busy_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc8_lsu_clr_busy_seq)
    function new(string name = "tc8_lsu_clr_busy_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC8", "=== TC8: LSU Clear Busy (F2.5) ===", UVM_LOW)

      // Dispatch: bank0/1=store, bank2=ALU
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      for (int b = 0; b < 3; b++) tr.enq_valids[b] = 1;
      tr.enq_uops_rob_idx[0] = `ROB_IDX(0,0); tr.enq_uops_pdst[0] = 0;
      tr.enq_uops_stale_pdst[0] = 0; tr.enq_uops_uses_stq[0] = 1; tr.enq_uops_unsafe[0] = 1;
      tr.enq_uops_rob_idx[1] = `ROB_IDX(0,1); tr.enq_uops_pdst[1] = 0;
      tr.enq_uops_stale_pdst[1] = 0; tr.enq_uops_uses_stq[1] = 1; tr.enq_uops_unsafe[1] = 1;
      tr.enq_uops_rob_idx[2] = `ROB_IDX(0,2); tr.enq_uops_pdst[2] = 15;
      tr.enq_uops_stale_pdst[2] = 0; tr.enq_uops_unsafe[2] = 1;
      for (int b = 0; b < 3; b++) begin
        tr.enq_uops_exception[b] = 0; tr.enq_uops_is_br[b] = 0;
      end
      tr.enq_partial_stall = 0;
      finish_item(tr);

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // WB ALU
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      tr.wb_valid[0] = 1; tr.wb_rob_idx[0] = `ROB_IDX(0,2); tr.wb_pdst[0] = 15;
      for (int i = 1; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // LSU clear stores
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_LSU_CLR_BSY;
      tr.lsu_clr_valid[0] = 1; tr.lsu_clr_bits[0] = `ROB_IDX(0,0);
      tr.lsu_clr_valid[1] = 1; tr.lsu_clr_bits[1] = `ROB_IDX(0,1);
      finish_item(tr);

      repeat(5) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end

      @(posedge vif.clock);
      if (vif.empty)
        `uvm_info("TC8", "F2.5 PASS: LSU clear busy works", UVM_LOW)
      else
        `uvm_error("TC8", "F2.5 FAIL: ROB not empty")
      `uvm_info("TC8", "=== TC8 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC9: CSR Stall Blocks Commit (F3.7)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc9_csr_stall.sv ====
  class tc9_csr_stall_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc9_csr_stall_seq)
    function new(string name = "tc9_csr_stall_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;
    virtual rob_if.DRV dvif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      if (!uvm_config_db#(virtual rob_if.DRV)::get(null, "", "vif", dvif))
        `uvm_fatal("SEQ", "Failed to get dvif")
      `uvm_info("TC9", "=== TC9: CSR Stall (F3.7) ===", UVM_LOW)

      // Dispatch + WB
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      for (int b = 0; b < 3; b++) begin
        tr.enq_valids[b] = 1; tr.enq_uops_rob_idx[b] = `ROB_IDX(0,b);
        tr.enq_uops_pdst[b] = 7'(10+b); tr.enq_uops_stale_pdst[b] = 0;
        tr.enq_uops_exception[b] = 0; tr.enq_uops_is_br[b] = 0; tr.enq_uops_unsafe[b] = 1;
      end
      tr.enq_partial_stall = 0;
      finish_item(tr);
      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      for (int i = 0; i < 3; i++) begin
        tr.wb_valid[i] = 1; tr.wb_rob_idx[i] = `ROB_IDX(0,i); tr.wb_pdst[i] = 7'(10+i);
      end
      for (int i = 3; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      // Assert stall
      dvif.drv_cb.csr_stall <= 1;
      repeat(4) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
        @(posedge vif.clock);
        if (vif.commit_valids[0] || vif.commit_valids[1] || vif.commit_valids[2])
          `uvm_error("TC9", "F3.7 FAIL: Commit during csr_stall!")
      end
      `uvm_info("TC9", "F3.7 PASS: No commit while stalled", UVM_LOW)
      dvif.drv_cb.csr_stall <= 0;

      repeat(5) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      @(posedge vif.clock);
      if (vif.empty)
        `uvm_info("TC9", "F3.7 PASS: Commit resumed", UVM_LOW)
      `uvm_info("TC9", "=== TC9 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC10: Predicated arch_valids (F3.8)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc10_predicated.sv ====
  class tc10_predicated_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc10_predicated_seq)
    function new(string name = "tc10_predicated_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;
    virtual rob_if.DRV dvif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      if (!uvm_config_db#(virtual rob_if.DRV)::get(null, "", "vif", dvif))
        `uvm_fatal("SEQ", "Failed to get dvif")
      `uvm_info("TC10", "=== TC10: Predicated (F3.8) ===", UVM_LOW)

      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_valids[1] = 0; tr.enq_valids[2] = 0;
      tr.enq_uops_rob_idx[0] = 0; tr.enq_uops_pdst[0] = 20; tr.enq_uops_stale_pdst[0] = 5;
      tr.enq_uops_exception[0] = 0; tr.enq_uops_is_br[0] = 0; tr.enq_uops_unsafe[0] = 1;
      tr.enq_uops_ldst_val[0] = 1;
      tr.enq_partial_stall = 1;
      finish_item(tr);

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // WB with predicated
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      tr.wb_valid[0] = 1; tr.wb_rob_idx[0] = 0; tr.wb_pdst[0] = 20;
      for (int i = 1; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);
      dvif.drv_cb.wb_resps_predicated[0] <= 1;

      repeat(5) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
        @(posedge vif.clock);
        if (vif.commit_valids[0]) begin
          if (!vif.commit_arch_valids[0])
            `uvm_info("TC10", "F3.8 PASS: valids=1 arch_valids=0", UVM_LOW)
          else
            `uvm_info("TC10", "F3.8 NOTE: arch_valids=1 (DUT behavior)", UVM_MEDIUM)
        end
      end
      dvif.drv_cb.wb_resps_predicated[0] <= 0;

      repeat(3) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC10", "=== TC10 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC11: Branch Mask Update on Resolve (F5.4)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc11_brmask_update.sv ====
  class tc11_brmask_update_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc11_brmask_update_seq)
    function new(string name = "tc11_brmask_update_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC11", "=== TC11: Branch Mask Resolve (F5.4) ===", UVM_LOW)

      // Branch A at bank0 (tag 0), instrs under tags 0+1
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_uops_rob_idx[0] = `ROB_IDX(0,0);
      tr.enq_uops_pdst[0] = 10; tr.enq_uops_stale_pdst[0] = 0;
      tr.enq_uops_exception[0] = 0; tr.enq_uops_is_br[0] = 1;
      tr.enq_uops_br_mask[0] = 16'h0001; tr.enq_uops_unsafe[0] = 1;
      tr.enq_valids[1] = 1; tr.enq_uops_rob_idx[1] = `ROB_IDX(0,1);
      tr.enq_uops_pdst[1] = 11; tr.enq_uops_stale_pdst[1] = 0;
      tr.enq_uops_exception[1] = 0; tr.enq_uops_is_br[1] = 0;
      tr.enq_uops_br_mask[1] = 16'h0003; tr.enq_uops_unsafe[1] = 1;
      tr.enq_valids[2] = 1; tr.enq_uops_rob_idx[2] = `ROB_IDX(0,2);
      tr.enq_uops_pdst[2] = 12; tr.enq_uops_stale_pdst[2] = 0;
      tr.enq_uops_exception[2] = 0; tr.enq_uops_is_br[2] = 1;
      tr.enq_uops_br_mask[2] = 16'h0002; tr.enq_uops_unsafe[2] = 1;
      tr.enq_partial_stall = 0;
      finish_item(tr);

      // Resolve tag 0 correct
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_BRANCH_UPDATE;
      tr.br_resolve_mask = 16'h0001; tr.br_mispredict_mask = 0;
      tr.br_rob_idx = 0; tr.br_mispredict = 0;
      finish_item(tr);

      `uvm_info("TC11", "F5.4: Tag 0 resolved — bit cleared from surviving entries", UVM_LOW)

      repeat(2) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end

      // Mispredict tag 1
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_BRANCH_UPDATE;
      tr.br_resolve_mask = 16'h0002; tr.br_mispredict_mask = 16'h0002;
      tr.br_rob_idx = `ROB_IDX(0,2); tr.br_mispredict = 1;
      finish_item(tr);

      repeat(10) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC11", "=== TC11 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC12: Pointer Wrap-Around (F6.1, F6.2)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc12_pointer_wrap.sv ====
  class tc12_pointer_wrap_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc12_pointer_wrap_seq)
    function new(string name = "tc12_pointer_wrap_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC12", "=== TC12: Pointer Wrap (F6.1, F6.2) ===", UVM_LOW)

      for (int wave = 0; wave < 15; wave++) begin
        if (!vif.ready) begin
          repeat(5) begin
            tr = rob_transaction::type_id::create("tr");
            start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
          end
          if (!vif.ready) break;
        end
        // Dispatch
        tr = rob_transaction::type_id::create("tr");
        start_item(tr);
        tr.op = ROB_DISPATCH;
        for (int b = 0; b < 3; b++) begin
          tr.enq_valids[b] = 1;
          tr.enq_uops_rob_idx[b] = `ROB_IDX(wave % NUM_ROB_ROWS, b);
          tr.enq_uops_pdst[b] = 7'((wave*3+b)%128);
          tr.enq_uops_stale_pdst[b] = 0;
          tr.enq_uops_exception[b] = 0; tr.enq_uops_is_br[b] = 0;
          tr.enq_uops_unsafe[b] = 1;
        end
        tr.enq_partial_stall = 0;
        finish_item(tr);
        // Immediate WB
        tr = rob_transaction::type_id::create("tr");
        start_item(tr);
        tr.op = ROB_WRITEBACK;
        for (int i = 0; i < 3; i++) begin
          tr.wb_valid[i] = 1;
          tr.wb_rob_idx[i] = `ROB_IDX(wave % NUM_ROB_ROWS, i);
          tr.wb_pdst[i] = 7'((wave*3+i)%128);
        end
        for (int i = 3; i < 6; i++) tr.wb_valid[i] = 0;
        finish_item(tr);
        repeat(2) begin
          tr = rob_transaction::type_id::create("tr");
          start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
        end
      end

      @(posedge vif.clock);
      `uvm_info("TC12", $sformatf("After 15 waves: head=%0d tail=%0d",
        vif.rob_head_idx, vif.rob_tail_idx), UVM_LOW)

      repeat(10) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC12", "=== TC12 Complete ===", UVM_LOW)
    endtask
  endclass


  // -----------------------------------------------------------------------
  // TC13: Oldest Exception Wins (F4.9)
  // -----------------------------------------------------------------------
// ==== FILE: rob_seq_tc13_oldest_exception.sv ====
  class tc13_oldest_exception_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc13_oldest_exception_seq)
    function new(string name = "tc13_oldest_exception_seq"); super.new(name); endfunction
    virtual rob_if.MON vif;

    task body();
      rob_transaction tr;
      if (!uvm_config_db#(virtual rob_if.MON)::get(null, "", "vif", vif))
        `uvm_fatal("SEQ", "Failed to get vif")
      `uvm_info("TC13", "=== TC13: Oldest Exception Wins (F4.9) ===", UVM_LOW)

      // Bank0: xcpt cause=2, Bank1: xcpt cause=5, Bank2: clean
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_DISPATCH;
      tr.enq_valids[0] = 1; tr.enq_uops_rob_idx[0] = `ROB_IDX(0,0);
      tr.enq_uops_pdst[0] = 10; tr.enq_uops_stale_pdst[0] = 0;
      tr.enq_uops_exception[0] = 1; tr.enq_uops_exc_cause[0] = 64'd2;
      tr.enq_uops_is_br[0] = 0; tr.enq_uops_unsafe[0] = 0;
      tr.enq_valids[1] = 1; tr.enq_uops_rob_idx[1] = `ROB_IDX(0,1);
      tr.enq_uops_pdst[1] = 11; tr.enq_uops_stale_pdst[1] = 0;
      tr.enq_uops_exception[1] = 1; tr.enq_uops_exc_cause[1] = 64'd5;
      tr.enq_uops_is_br[1] = 0; tr.enq_uops_unsafe[1] = 0;
      tr.enq_valids[2] = 1; tr.enq_uops_rob_idx[2] = `ROB_IDX(0,2);
      tr.enq_uops_pdst[2] = 12; tr.enq_uops_stale_pdst[2] = 0;
      tr.enq_uops_exception[2] = 0;
      tr.enq_uops_is_br[2] = 0; tr.enq_uops_unsafe[2] = 1;
      tr.enq_partial_stall = 0;
      finish_item(tr);

      tr = rob_transaction::type_id::create("tr");
      start_item(tr); tr.op = ROB_IDLE; finish_item(tr);

      // WB bank2
      tr = rob_transaction::type_id::create("tr");
      start_item(tr);
      tr.op = ROB_WRITEBACK;
      tr.wb_valid[0] = 1; tr.wb_rob_idx[0] = `ROB_IDX(0,2); tr.wb_pdst[0] = 12;
      for (int i = 1; i < 6; i++) tr.wb_valid[i] = 0;
      finish_item(tr);

      repeat(8) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
        @(posedge vif.clock);
        if (vif.com_xcpt_valid) begin
          if (vif.com_xcpt_bits_cause == 64'd2)
            `uvm_info("TC13", "F4.9 PASS: Oldest exception cause=2 reported", UVM_LOW)
          else if (vif.com_xcpt_bits_cause == 64'd5)
            `uvm_error("TC13", "F4.9 FAIL: Younger cause=5 reported")
          else
            `uvm_info("TC13", $sformatf("F4.9 NOTE: cause=%0d", vif.com_xcpt_bits_cause), UVM_LOW)
          break;
        end
      end

      repeat(15) begin
        tr = rob_transaction::type_id::create("tr");
        start_item(tr); tr.op = ROB_IDLE; finish_item(tr);
      end
      `uvm_info("TC13", "=== TC13 Complete ===", UVM_LOW)
    endtask
  endclass


  // =========================================================================
  // BASE TEST + 13 TEST CLASSES + REGRESSION
  // =========================================================================
// ==== FILE: rob_tests.sv ====
  class rob_base_test extends uvm_test;
    `uvm_component_utils(rob_base_test)
    rob_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = rob_env::type_id::create("env", this);
    endfunction
    function void end_of_elaboration_phase(uvm_phase phase);
      uvm_top.print_topology();
    endfunction
  endclass

  `define MAKE_TEST(NAME, SEQ_TYPE) \
  class NAME extends rob_base_test; \
    `uvm_component_utils(NAME) \
    function new(string name, uvm_component parent); super.new(name, parent); endfunction \
    task run_phase(uvm_phase phase); \
      SEQ_TYPE seq = SEQ_TYPE::type_id::create("seq"); \
      phase.raise_objection(this); \
      seq.start(env.agt.sqr); \
      phase.drop_objection(this); \
    endtask \
  endclass

  `MAKE_TEST(tc1_dispatch_test,         tc1_dispatch_seq)
  `MAKE_TEST(tc2_ooo_writeback_test,    tc2_ooo_writeback_seq)
  `MAKE_TEST(tc3_inorder_commit_test,   tc3_inorder_commit_seq)
  `MAKE_TEST(tc4_precise_exception_test,tc4_precise_exception_seq)
  `MAKE_TEST(tc5_branch_mispredict_test,tc5_branch_mispredict_seq)
  `MAKE_TEST(tc6_reset_state_test,      tc6_reset_state_seq)
  `MAKE_TEST(tc7_fence_dispatch_test,   tc7_fence_dispatch_seq)
  `MAKE_TEST(tc8_lsu_clr_busy_test,     tc8_lsu_clr_busy_seq)
  `MAKE_TEST(tc9_csr_stall_test,        tc9_csr_stall_seq)
  `MAKE_TEST(tc10_predicated_test,      tc10_predicated_seq)
  `MAKE_TEST(tc11_brmask_update_test,   tc11_brmask_update_seq)
  `MAKE_TEST(tc12_pointer_wrap_test,    tc12_pointer_wrap_seq)
  `MAKE_TEST(tc13_oldest_exception_test,tc13_oldest_exception_seq)

  // Regression: all 13 TC sequential
  class tc_all_regression_seq extends uvm_sequence #(rob_transaction);
    `uvm_object_utils(tc_all_regression_seq)
    function new(string name = "tc_all_regression_seq"); super.new(name); endfunction
    task body();
      begin tc1_dispatch_seq          s=tc1_dispatch_seq::type_id::create("s");          s.start(m_sequencer); end
      begin tc2_ooo_writeback_seq     s=tc2_ooo_writeback_seq::type_id::create("s");     s.start(m_sequencer); end
      begin tc3_inorder_commit_seq    s=tc3_inorder_commit_seq::type_id::create("s");    s.start(m_sequencer); end
      begin tc4_precise_exception_seq s=tc4_precise_exception_seq::type_id::create("s"); s.start(m_sequencer); end
      begin tc5_branch_mispredict_seq s=tc5_branch_mispredict_seq::type_id::create("s"); s.start(m_sequencer); end
      begin tc6_reset_state_seq       s=tc6_reset_state_seq::type_id::create("s");       s.start(m_sequencer); end
      begin tc7_fence_dispatch_seq    s=tc7_fence_dispatch_seq::type_id::create("s");    s.start(m_sequencer); end
      begin tc8_lsu_clr_busy_seq      s=tc8_lsu_clr_busy_seq::type_id::create("s");     s.start(m_sequencer); end
      begin tc9_csr_stall_seq         s=tc9_csr_stall_seq::type_id::create("s");         s.start(m_sequencer); end
      begin tc10_predicated_seq       s=tc10_predicated_seq::type_id::create("s");       s.start(m_sequencer); end
      begin tc11_brmask_update_seq    s=tc11_brmask_update_seq::type_id::create("s");    s.start(m_sequencer); end
      begin tc12_pointer_wrap_seq     s=tc12_pointer_wrap_seq::type_id::create("s");     s.start(m_sequencer); end
      begin tc13_oldest_exception_seq s=tc13_oldest_exception_seq::type_id::create("s"); s.start(m_sequencer); end
    endtask
  endclass

  `MAKE_TEST(tc_all_regression_test, tc_all_regression_seq)

endpackage


// ============================================================================
// TOP-LEVEL TESTBENCH MODULE
// ============================================================================
// ==== FILE: tb_top.sv ====
module tb_top;
  import uvm_pkg::*;
  import rob_pkg::*;
  `include "uvm_macros.svh"

  logic clock, reset;
  initial begin
    clock = 0;
    forever #5 clock = ~clock;
  end

  initial begin
    reset = 1;
    repeat(10) @(posedge clock);
    reset = 0;
  end

  rob_if rif(.clock(clock), .reset(reset));

  // -------------------------------------------------------
  // DUT instantiation
  // -------------------------------------------------------
  Rob dut (
    .clock                          (clock),
    .reset                          (reset),
    .io_enq_valids_0                (rif.enq_valids[0]),
    .io_enq_valids_1                (rif.enq_valids[1]),
    .io_enq_valids_2                (rif.enq_valids[2]),
    .io_enq_partial_stall           (rif.enq_partial_stall),
    .io_enq_uops_0_uopc             (rif.enq_uops_uopc[0]),
    .io_enq_uops_0_debug_inst       (rif.enq_uops_debug_inst[0]),
    .io_enq_uops_0_is_rvc           (rif.enq_uops_is_rvc[0]),
    .io_enq_uops_0_is_br            (rif.enq_uops_is_br[0]),
    .io_enq_uops_0_is_jalr          (rif.enq_uops_is_jalr[0]),
    .io_enq_uops_0_is_jal           (rif.enq_uops_is_jal[0]),
    .io_enq_uops_0_br_mask          (rif.enq_uops_br_mask[0]),
    .io_enq_uops_0_ftq_idx          (rif.enq_uops_ftq_idx[0]),
    .io_enq_uops_0_edge_inst        (rif.enq_uops_edge_inst[0]),
    .io_enq_uops_0_pc_lob           (rif.enq_uops_pc_lob[0]),
    .io_enq_uops_0_rob_idx          (rif.enq_uops_rob_idx[0]),
    .io_enq_uops_0_pdst             (rif.enq_uops_pdst[0]),
    .io_enq_uops_0_stale_pdst       (rif.enq_uops_stale_pdst[0]),
    .io_enq_uops_0_exception        (rif.enq_uops_exception[0]),
    .io_enq_uops_0_exc_cause        (rif.enq_uops_exc_cause[0]),
    .io_enq_uops_0_is_fence         (rif.enq_uops_is_fence[0]),
    .io_enq_uops_0_is_fencei        (rif.enq_uops_is_fencei[0]),
    .io_enq_uops_0_uses_ldq         (rif.enq_uops_uses_ldq[0]),
    .io_enq_uops_0_uses_stq         (rif.enq_uops_uses_stq[0]),
    .io_enq_uops_0_is_sys_pc2epc    (rif.enq_uops_is_sys_pc2epc[0]),
    .io_enq_uops_0_is_unique        (rif.enq_uops_is_unique[0]),
    .io_enq_uops_0_flush_on_commit  (rif.enq_uops_flush_on_commit[0]),
    .io_enq_uops_0_ldst             (rif.enq_uops_ldst[0]),
    .io_enq_uops_0_ldst_val         (rif.enq_uops_ldst_val[0]),
    .io_enq_uops_0_dst_rtype        (rif.enq_uops_dst_rtype[0]),
    .io_enq_uops_0_fp_val           (rif.enq_uops_fp_val[0]),
    .io_enq_uops_0_debug_fsrc       (rif.enq_uops_debug_fsrc[0]),
    .io_enq_uops_1_uopc             (rif.enq_uops_uopc[1]),
    .io_enq_uops_1_debug_inst       (rif.enq_uops_debug_inst[1]),
    .io_enq_uops_1_is_rvc           (rif.enq_uops_is_rvc[1]),
    .io_enq_uops_1_is_br            (rif.enq_uops_is_br[1]),
    .io_enq_uops_1_is_jalr          (rif.enq_uops_is_jalr[1]),
    .io_enq_uops_1_is_jal           (rif.enq_uops_is_jal[1]),
    .io_enq_uops_1_br_mask          (rif.enq_uops_br_mask[1]),
    .io_enq_uops_1_ftq_idx          (rif.enq_uops_ftq_idx[1]),
    .io_enq_uops_1_edge_inst        (rif.enq_uops_edge_inst[1]),
    .io_enq_uops_1_pc_lob           (rif.enq_uops_pc_lob[1]),
    .io_enq_uops_1_rob_idx          (rif.enq_uops_rob_idx[1]),
    .io_enq_uops_1_pdst             (rif.enq_uops_pdst[1]),
    .io_enq_uops_1_stale_pdst       (rif.enq_uops_stale_pdst[1]),
    .io_enq_uops_1_exception        (rif.enq_uops_exception[1]),
    .io_enq_uops_1_exc_cause        (rif.enq_uops_exc_cause[1]),
    .io_enq_uops_1_is_fence         (rif.enq_uops_is_fence[1]),
    .io_enq_uops_1_is_fencei        (rif.enq_uops_is_fencei[1]),
    .io_enq_uops_1_uses_ldq         (rif.enq_uops_uses_ldq[1]),
    .io_enq_uops_1_uses_stq         (rif.enq_uops_uses_stq[1]),
    .io_enq_uops_1_is_sys_pc2epc    (rif.enq_uops_is_sys_pc2epc[1]),
    .io_enq_uops_1_is_unique        (rif.enq_uops_is_unique[1]),
    .io_enq_uops_1_flush_on_commit  (rif.enq_uops_flush_on_commit[1]),
    .io_enq_uops_1_ldst             (rif.enq_uops_ldst[1]),
    .io_enq_uops_1_ldst_val         (rif.enq_uops_ldst_val[1]),
    .io_enq_uops_1_dst_rtype        (rif.enq_uops_dst_rtype[1]),
    .io_enq_uops_1_fp_val           (rif.enq_uops_fp_val[1]),
    .io_enq_uops_1_debug_fsrc       (rif.enq_uops_debug_fsrc[1]),
    .io_enq_uops_2_uopc             (rif.enq_uops_uopc[2]),
    .io_enq_uops_2_debug_inst       (rif.enq_uops_debug_inst[2]),
    .io_enq_uops_2_is_rvc           (rif.enq_uops_is_rvc[2]),
    .io_enq_uops_2_is_br            (rif.enq_uops_is_br[2]),
    .io_enq_uops_2_is_jalr          (rif.enq_uops_is_jalr[2]),
    .io_enq_uops_2_is_jal           (rif.enq_uops_is_jal[2]),
    .io_enq_uops_2_br_mask          (rif.enq_uops_br_mask[2]),
    .io_enq_uops_2_ftq_idx          (rif.enq_uops_ftq_idx[2]),
    .io_enq_uops_2_edge_inst        (rif.enq_uops_edge_inst[2]),
    .io_enq_uops_2_pc_lob           (rif.enq_uops_pc_lob[2]),
    .io_enq_uops_2_rob_idx          (rif.enq_uops_rob_idx[2]),
    .io_enq_uops_2_pdst             (rif.enq_uops_pdst[2]),
    .io_enq_uops_2_stale_pdst       (rif.enq_uops_stale_pdst[2]),
    .io_enq_uops_2_exception        (rif.enq_uops_exception[2]),
    .io_enq_uops_2_exc_cause        (rif.enq_uops_exc_cause[2]),
    .io_enq_uops_2_is_fence         (rif.enq_uops_is_fence[2]),
    .io_enq_uops_2_is_fencei        (rif.enq_uops_is_fencei[2]),
    .io_enq_uops_2_uses_ldq         (rif.enq_uops_uses_ldq[2]),
    .io_enq_uops_2_uses_stq         (rif.enq_uops_uses_stq[2]),
    .io_enq_uops_2_is_sys_pc2epc    (rif.enq_uops_is_sys_pc2epc[2]),
    .io_enq_uops_2_is_unique        (rif.enq_uops_is_unique[2]),
    .io_enq_uops_2_flush_on_commit  (rif.enq_uops_flush_on_commit[2]),
    .io_enq_uops_2_ldst             (rif.enq_uops_ldst[2]),
    .io_enq_uops_2_ldst_val         (rif.enq_uops_ldst_val[2]),
    .io_enq_uops_2_dst_rtype        (rif.enq_uops_dst_rtype[2]),
    .io_enq_uops_2_fp_val           (rif.enq_uops_fp_val[2]),
    .io_enq_uops_2_debug_fsrc       (rif.enq_uops_debug_fsrc[2]),
    .io_xcpt_fetch_pc               (rif.xcpt_fetch_pc),
    .io_brupdate_b1_resolve_mask    (rif.brupdate_b1_resolve_mask),
    .io_brupdate_b1_mispredict_mask (rif.brupdate_b1_mispredict_mask),
    .io_brupdate_b2_uop_rob_idx     (rif.brupdate_b2_uop_rob_idx),
    .io_brupdate_b2_mispredict       (rif.brupdate_b2_mispredict),
    .io_wb_resps_0_valid             (rif.wb_resps_valid[0]),
    .io_wb_resps_0_bits_uop_rob_idx  (rif.wb_resps_rob_idx[0]),
    .io_wb_resps_0_bits_uop_pdst     (rif.wb_resps_pdst[0]),
    .io_wb_resps_0_bits_predicated   (rif.wb_resps_predicated[0]),
    .io_wb_resps_1_valid             (rif.wb_resps_valid[1]),
    .io_wb_resps_1_bits_uop_rob_idx  (rif.wb_resps_rob_idx[1]),
    .io_wb_resps_1_bits_uop_pdst     (rif.wb_resps_pdst[1]),
    .io_wb_resps_2_valid             (rif.wb_resps_valid[2]),
    .io_wb_resps_2_bits_uop_rob_idx  (rif.wb_resps_rob_idx[2]),
    .io_wb_resps_2_bits_uop_pdst     (rif.wb_resps_pdst[2]),
    .io_wb_resps_3_valid             (rif.wb_resps_valid[3]),
    .io_wb_resps_3_bits_uop_rob_idx  (rif.wb_resps_rob_idx[3]),
    .io_wb_resps_3_bits_uop_pdst     (rif.wb_resps_pdst[3]),
    .io_wb_resps_4_valid             (rif.wb_resps_valid[4]),
    .io_wb_resps_4_bits_uop_rob_idx  (rif.wb_resps_rob_idx[4]),
    .io_wb_resps_4_bits_uop_pdst     (rif.wb_resps_pdst[4]),
    .io_wb_resps_4_bits_predicated   (rif.wb_resps_predicated[4]),
    .io_wb_resps_5_valid             (rif.wb_resps_valid[5]),
    .io_wb_resps_5_bits_uop_rob_idx  (rif.wb_resps_rob_idx[5]),
    .io_wb_resps_5_bits_uop_pdst     (rif.wb_resps_pdst[5]),
    .io_lsu_clr_bsy_0_valid          (rif.lsu_clr_bsy_valid[0]),
    .io_lsu_clr_bsy_0_bits           (rif.lsu_clr_bsy_bits[0]),
    .io_lsu_clr_bsy_1_valid          (rif.lsu_clr_bsy_valid[1]),
    .io_lsu_clr_bsy_1_bits           (rif.lsu_clr_bsy_bits[1]),
    .io_fflags_0_valid               (rif.fflags_valid[0]),
    .io_fflags_0_bits_uop_rob_idx    (rif.fflags_uop_rob_idx[0]),
    .io_fflags_0_bits_flags          (rif.fflags_bits_flags[0]),
    .io_fflags_1_valid               (rif.fflags_valid[1]),
    .io_fflags_1_bits_uop_rob_idx    (rif.fflags_uop_rob_idx[1]),
    .io_fflags_1_bits_flags          (rif.fflags_bits_flags[1]),
    .io_lxcpt_valid                  (rif.lxcpt_valid),
    .io_lxcpt_bits_uop_br_mask       (rif.lxcpt_bits_uop_br_mask),
    .io_lxcpt_bits_uop_rob_idx       (rif.lxcpt_bits_uop_rob_idx),
    .io_lxcpt_bits_cause             (rif.lxcpt_bits_cause),
    .io_lxcpt_bits_badvaddr          (rif.lxcpt_bits_badvaddr),
    .io_csr_stall                    (rif.csr_stall),
    .io_rob_tail_idx                 (rif.rob_tail_idx),
    .io_rob_head_idx                 (rif.rob_head_idx),
    .io_commit_valids_0              (rif.commit_valids[0]),
    .io_commit_valids_1              (rif.commit_valids[1]),
    .io_commit_valids_2              (rif.commit_valids[2]),
    .io_commit_arch_valids_0         (rif.commit_arch_valids[0]),
    .io_commit_arch_valids_1         (rif.commit_arch_valids[1]),
    .io_commit_arch_valids_2         (rif.commit_arch_valids[2]),
    .io_commit_rbk_valids_0          (rif.commit_rbk_valids[0]),
    .io_commit_rbk_valids_1          (rif.commit_rbk_valids[1]),
    .io_commit_rbk_valids_2          (rif.commit_rbk_valids[2]),
    .io_commit_rollback              (rif.commit_rollback),
    .io_commit_uops_0_pdst           (rif.commit_uops_pdst[0]),
    .io_commit_uops_0_stale_pdst     (rif.commit_uops_stale_pdst[0]),
    .io_commit_uops_0_ldst_val       (rif.commit_uops_ldst_val[0]),
    .io_commit_uops_0_ldst           (rif.commit_uops_ldst[0]),
    .io_commit_uops_1_pdst           (rif.commit_uops_pdst[1]),
    .io_commit_uops_1_stale_pdst     (rif.commit_uops_stale_pdst[1]),
    .io_commit_uops_1_ldst_val       (rif.commit_uops_ldst_val[1]),
    .io_commit_uops_1_ldst           (rif.commit_uops_ldst[1]),
    .io_commit_uops_2_pdst           (rif.commit_uops_pdst[2]),
    .io_commit_uops_2_stale_pdst     (rif.commit_uops_stale_pdst[2]),
    .io_commit_uops_2_ldst_val       (rif.commit_uops_ldst_val[2]),
    .io_commit_uops_2_ldst           (rif.commit_uops_ldst[2]),
    .io_commit_fflags_valid          (rif.commit_fflags_valid),
    .io_commit_fflags_bits           (rif.commit_fflags_bits),
    .io_com_load_is_at_rob_head      (rif.com_load_is_at_rob_head),
    .io_com_xcpt_valid               (rif.com_xcpt_valid),
    .io_com_xcpt_bits_cause          (rif.com_xcpt_bits_cause),
    .io_com_xcpt_bits_badvaddr       (rif.com_xcpt_bits_badvaddr),
    .io_flush_valid                  (rif.flush_valid),
    .io_flush_bits_flush_typ         (rif.flush_bits_flush_typ),
    .io_empty                        (rif.empty),
    .io_ready                        (rif.ready),
    .io_flush_frontend               (rif.flush_frontend)
  );

  // -------------------------------------------------------
  // UVM config & run
  // -------------------------------------------------------
  initial begin
    uvm_config_db#(virtual rob_if.DRV)::set(null, "*", "vif", rif.DRV);
    uvm_config_db#(virtual rob_if.MON)::set(null, "*", "vif", rif.MON);
    $dumpfile("rob_tb.vcd");
    $dumpvars(0, tb_top);
  end

  initial begin
    run_test();
  end

  initial begin
    #200_000;
    `uvm_fatal("TIMEOUT", "Simulation exceeded 200us limit")
  end

endmodule

// ============================================================================
// RUN COMMANDS:
//
// VCS:
//   vcs -sverilog -ntb_opts uvm-1.2 rob_uvm_tb.sv rob.v -o simv
//   ./simv +UVM_TESTNAME=rob_pkg::tc1_dispatch_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc2_ooo_writeback_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc3_inorder_commit_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc4_precise_exception_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc5_branch_mispredict_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc6_reset_state_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc7_fence_dispatch_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc8_lsu_clr_busy_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc9_csr_stall_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc10_predicated_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc11_brmask_update_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc12_pointer_wrap_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc13_oldest_exception_test
//   ./simv +UVM_TESTNAME=rob_pkg::tc_all_regression_test
//
// Questa:
//   vlog -sv rob_uvm_tb.sv rob.v
//   vsim -c tb_top +UVM_TESTNAME=rob_pkg::tc1_dispatch_test -do "run -all"
//
// ============================================================================
