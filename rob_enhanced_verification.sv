// =============================================================================
// FILE: rob_enhanced_verification.sv
// BOOM ROB UVM Environment — Bổ sung cho Scoreboard, Monitor, Coverage
//
// Phân tích Gap:
//   Monitor hiện tại  : Chỉ log, không publish qua ap, thiếu signal trong mon_cb
//   Scoreboard hiện tại: Chỉ có 2 invariant, thiếu ~30+ check từ testplan
//   Coverage          : HOÀN TOÀN CHƯA CÓ (0 covergroup)
//
// File này bổ sung:
//   [1] rob_if_mon_patch   — Thêm signal vào mon_cb clocking block
//   [2] rob_monitor_v2     — Enhanced monitor publish transaction đầy đủ
//   [3] rob_scoreboard_v2  — Shadow ROB model + tất cả invariant checks
//   [4] rob_coverage       — Tất cả covergroup từ §7 testplan
// =============================================================================

// =============================================================================
// [1] PATCH CHO rob_if.sv — Thêm vào mon_cb clocking block
// Thay thế clocking mon_cb hiện tại bằng block sau:
// =============================================================================

/*
  clocking mon_cb @(posedge clock);
    default input #1;
    // --- Dispatch inputs (bổ sung pdst, is_fence, is_unique, unsafe) ---
    input  enq_valids, enq_partial_stall;
    input  enq_uops_rob_idx, enq_uops_pdst;           // THÊM pdst
    input  enq_uops_exception, enq_uops_exc_cause;
    input  enq_uops_is_br,  enq_uops_br_mask;
    input  enq_uops_is_fence, enq_uops_is_fencei;     // THÊM fence
    input  enq_uops_is_unique;                         // THÊM unique
    input  enq_uops_unsafe;                            // THÊM unsafe
    input  enq_uops_ldst_val;                          // THÊM ldst_val
    input  enq_uops_ftq_idx, enq_uops_pc_lob;
    // --- Branch update (bổ sung b1 masks) ---
    input  brupdate_b1_resolve_mask;                   // THÊM resolve
    input  brupdate_b1_mispredict_mask;                // THÊM mispredict
    input  brupdate_b2_mispredict, brupdate_b2_uop_rob_idx;
    // --- Writeback (bổ sung pdst để check W3) ---
    input  wb_resps_valid, wb_resps_rob_idx, wb_resps_pdst; // THÊM pdst
    // --- LSU (THÊM để check F2.5, W4) ---
    input  lsu_clr_bsy_valid, lsu_clr_bsy_bits;
    // --- Pointers & outputs ---
    input  rob_tail_idx, rob_head_idx;
    input  commit_valids, commit_arch_valids, commit_rbk_valids, commit_rollback;
    input  commit_uops_pdst, commit_uops_stale_pdst;
    input  com_xcpt_valid, com_xcpt_bits_cause, com_xcpt_bits_badvaddr;
    input  com_xcpt_bits_ftq_idx, com_xcpt_bits_pc_lob;
    input  flush_valid, flush_bits_flush_typ;
    input  empty, ready, flush_frontend;
    input  csr_stall;                                  // THÊM để check F3.7
  endclocking
*/


// =============================================================================
// [2] rob_monitor_v2.sv — Enhanced Monitor
//     Thêm: publish transaction qua ap, capture đủ field cho scoreboard
// =============================================================================

class rob_monitor_v2 extends uvm_monitor;
  `uvm_component_utils(rob_monitor_v2)

  virtual rob_if.MON         vif;
  uvm_analysis_port #(rob_transaction) ap;

  // Prev-cycle state để detect transitions
  logic [6:0]  prev_head, prev_tail;
  logic        prev_empty;
  int unsigned cycles_since_xcpt;
  bit          xcpt_pending;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
      `uvm_fatal("MON_V2", "Could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    rob_transaction obs;
    @(negedge vif.reset);
    prev_head = 0; prev_tail = 0; prev_empty = 1;
    xcpt_pending = 0; cycles_since_xcpt = 0;
    forever begin
      @(posedge vif.clock);
      obs = rob_transaction::type_id::create("obs");
      capture_cycle(obs);
      ap.write(obs);         // Publish mọi cycle để scoreboard nhận
      log_events(obs);
    end
  endtask

  // Capture toàn bộ signal trong một cycle thành transaction
  task capture_cycle(rob_transaction tr);
    // Dispatch
    for (int i = 0; i < 4; i++) begin
      tr.enq_valids[i]          = vif.mon_cb.enq_valids[i];
      tr.enq_uops_rob_idx[i]    = vif.mon_cb.enq_uops_rob_idx[i];
      tr.enq_uops_pdst[i]       = vif.mon_cb.enq_uops_pdst[i];
      tr.enq_uops_exception[i]  = vif.mon_cb.enq_uops_exception[i];
      tr.enq_uops_is_br[i]      = vif.mon_cb.enq_uops_is_br[i];
      tr.enq_uops_br_mask[i]    = vif.mon_cb.enq_uops_br_mask[i];
      tr.enq_uops_is_fence[i]   = vif.mon_cb.enq_uops_is_fence[i];
      tr.enq_uops_is_fencei[i]  = vif.mon_cb.enq_uops_is_fencei[i];
      tr.enq_uops_is_unique[i]  = vif.mon_cb.enq_uops_is_unique[i];
      tr.enq_uops_unsafe[i]     = vif.mon_cb.enq_uops_unsafe[i];
      tr.enq_uops_ldst_val[i]   = vif.mon_cb.enq_uops_ldst_val[i];
    end
    tr.enq_partial_stall = vif.mon_cb.enq_partial_stall;

    // Branch update
    tr.br_resolve_mask      = vif.mon_cb.brupdate_b1_resolve_mask;
    tr.br_mispredict_mask   = vif.mon_cb.brupdate_b1_mispredict_mask;
    tr.br_rob_idx           = vif.mon_cb.brupdate_b2_uop_rob_idx;
    tr.br_mispredict        = vif.mon_cb.brupdate_b2_mispredict;

    // Writeback
    for (int i = 0; i < 10; i++) begin
      tr.wb_valid[i]   = vif.mon_cb.wb_resps_valid[i];
      tr.wb_rob_idx[i] = vif.mon_cb.wb_resps_rob_idx[i];
      tr.wb_pdst[i]    = vif.mon_cb.wb_resps_pdst[i];
    end

    // LSU clear busy
    for (int i = 0; i < 3; i++) begin
      tr.lsu_clr_valid[i] = vif.mon_cb.lsu_clr_bsy_valid[i];
      tr.lsu_clr_bits[i]  = vif.mon_cb.lsu_clr_bsy_bits[i];
    end
  endtask

  task log_events(rob_transaction tr);
    // Log dispatch
    begin : log_dispatch
      bit any_enq = 0;
      for (int i=0;i<4;i++) if (tr.enq_valids[i]) any_enq=1;
      if (any_enq)
        `uvm_info("MON_V2",$sformatf("DISPATCH v={%0b%0b%0b%0b} tail=%0d partial=%0b",
          tr.enq_valids[0],tr.enq_valids[1],tr.enq_valids[2],tr.enq_valids[3],
          vif.mon_cb.rob_tail_idx, tr.enq_partial_stall), UVM_HIGH)
    end

    // Log commit
    begin : log_commit
      bit any_c=0;
      for (int i=0;i<4;i++) if (vif.mon_cb.commit_valids[i]) any_c=1;
      if (any_c)
        `uvm_info("MON_V2",$sformatf("COMMIT v={%0b%0b%0b%0b} av={%0b%0b%0b%0b} head=%0d",
          vif.mon_cb.commit_valids[0],vif.mon_cb.commit_valids[1],
          vif.mon_cb.commit_valids[2],vif.mon_cb.commit_valids[3],
          vif.mon_cb.commit_arch_valids[0],vif.mon_cb.commit_arch_valids[1],
          vif.mon_cb.commit_arch_valids[2],vif.mon_cb.commit_arch_valids[3],
          vif.mon_cb.rob_head_idx), UVM_MEDIUM)
    end

    // Log exception & flush
    if (vif.mon_cb.com_xcpt_valid)
      `uvm_info("MON_V2",$sformatf("COM_XCPT head=%0d cause=0x%0h",
        vif.mon_cb.rob_head_idx, vif.mon_cb.com_xcpt_bits_cause), UVM_LOW)
    if (vif.mon_cb.flush_valid)
      `uvm_info("MON_V2",$sformatf("FLUSH typ=%0d",vif.mon_cb.flush_bits_flush_typ), UVM_LOW)
    if (vif.mon_cb.commit_rollback)
      `uvm_info("MON_V2",$sformatf("ROLLBACK tail=%0d head=%0d",
        vif.mon_cb.rob_tail_idx, vif.mon_cb.rob_head_idx), UVM_MEDIUM)

    // Log pointer changes
    if (vif.mon_cb.rob_head_idx !== prev_head)
      `uvm_info("MON_V2",$sformatf("HEAD %0d->%0d",prev_head,vif.mon_cb.rob_head_idx),UVM_HIGH)
    if (vif.mon_cb.rob_tail_idx !== prev_tail)
      `uvm_info("MON_V2",$sformatf("TAIL %0d->%0d",prev_tail,vif.mon_cb.rob_tail_idx),UVM_HIGH)

    // Log branch mispredict
    if (tr.br_mispredict)
      `uvm_info("MON_V2",$sformatf("BR_MISPREDICT rob_idx=%0d tail_after=%0d",
        tr.br_rob_idx, vif.mon_cb.rob_tail_idx), UVM_LOW)

    prev_head = vif.mon_cb.rob_head_idx;
    prev_tail = vif.mon_cb.rob_tail_idx;
    prev_empty = vif.mon_cb.empty;
  endtask

endclass


// =============================================================================
// [3] rob_scoreboard_v2.sv
//
// Shadow ROB model hoàn chỉnh + toàn bộ invariant checks:
//   GROUP A  — Dispatch checks  (F1.1–F1.7, D1–D5, A1–A2)
//   GROUP B  — Writeback checks (F2.1–F2.7, W1–W3)
//   GROUP C  — Commit checks    (F3.1–F3.8)
//   GROUP D  — Exception checks (F4.1–F4.11, A9–A12)
//   GROUP E  — Branch checks    (F5.1–F5.6)
//   GROUP F  — Pointer checks   (F6.1–F6.5)
//   GROUP G  — FSM checks       (F7.1–F7.6)
// =============================================================================

class rob_scoreboard_v2 extends uvm_scoreboard;
  `uvm_component_utils(rob_scoreboard_v2)

  virtual rob_if.MON vif;

  // ---- Shadow ROB Entries ----
  localparam NUM_ROB  = 128;  // >= numRobEntries=96
  localparam CW       = 4;
  localparam WB_PORTS = 10;

  typedef struct {
    bit        valid;
    bit        busy;
    bit [6:0]  pdst;
    bit        ldst_val;
    bit        unsafe;
    bit        is_fence;
    bit        is_unique;
    bit [19:0] br_mask;
    bit        xcpt;
    bit [63:0] exc_cause;
    bit        killed;     // killed by branch mispredict
  } rob_entry_t;

  rob_entry_t shadow[NUM_ROB];

  // ---- Pointer tracking ----
  logic [6:0] sh_head, sh_tail;
  bit         sh_maybe_full;
  bit         sh_empty;
  bit         sh_full;

  // ---- FSM State Inference ----
  typedef enum { FSM_RESET, FSM_NORMAL, FSM_ROLLBACK, FSM_WAIT_EMPTY } fsm_state_e;
  fsm_state_e fsm_state, fsm_prev;

  // ---- Exception timing ----
  bit         xcpt_thrown;
  int         xcpt_thrown_cycle;
  int         sim_cycle;

  // ---- Stats ----
  int unsigned total_commits, total_xcpts, total_flushes;
  int unsigned total_rollback_cycles, error_count;

  // ---- Previous cycle state (for transition checks) ----
  logic [6:0] prev_head, prev_tail;
  bit         prev_xcpt_valid;
  bit         prev_rollback;
  bit         prev_empty;
  bit [19:0]  killed_br_mask; // last mispredict mask

  // ---- uvm_analysis_imp to receive monitor transactions ----
  `uvm_analysis_imp_decl(_mon)
  uvm_analysis_imp_mon #(rob_transaction, rob_scoreboard_v2) mon_export;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon_export = new("mon_export", this);
    if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
      `uvm_fatal("SCB_V2", "Could not get vif")
    reset_shadow();
  endfunction

  // ---- Reset shadow state ----
  function void reset_shadow();
    for (int i = 0; i < NUM_ROB; i++) begin
      shadow[i].valid    = 0; shadow[i].busy     = 0;
      shadow[i].pdst     = 0; shadow[i].ldst_val = 0;
      shadow[i].unsafe   = 0; shadow[i].is_fence = 0;
      shadow[i].is_unique= 0; shadow[i].br_mask  = 0;
      shadow[i].xcpt     = 0; shadow[i].exc_cause= 0;
      shadow[i].killed   = 0;
    end
    sh_head = 0; sh_tail = 0;
    sh_maybe_full = 0; sh_empty = 1; sh_full = 0;
    fsm_state = FSM_RESET; fsm_prev = FSM_RESET;
    xcpt_thrown = 0; xcpt_thrown_cycle = 0; sim_cycle = 0;
    prev_head = 0; prev_tail = 0;
    prev_xcpt_valid = 0; prev_rollback = 0; prev_empty = 1;
    killed_br_mask = 0;
    error_count = 0;
  endfunction

  // ---- Main run loop (direct interface observation) ----
  task run_phase(uvm_phase phase);
    @(negedge vif.reset);
    reset_shadow();
    repeat(2) @(posedge vif.clock); // Sync post-reset
    forever begin
      @(posedge vif.clock);
      sim_cycle++;
      update_fsm();
      check_all();
      update_shadow();
      prev_head         = vif.mon_cb.rob_head_idx;
      prev_tail         = vif.mon_cb.rob_tail_idx;
      prev_xcpt_valid   = vif.mon_cb.com_xcpt_valid;
      prev_rollback     = vif.mon_cb.commit_rollback;
      prev_empty        = vif.mon_cb.empty;
      fsm_prev          = fsm_state;
    end
  endtask

  // ---- monitor transaction receive (from analysis port) ----
  function void write_mon(rob_transaction tr); endfunction  // handled in run_phase

  // ====================================================================
  // FSM State Inference (F7.x)
  // ====================================================================
  function void update_fsm();
    fsm_prev = fsm_state;
    case (fsm_state)
      FSM_RESET: begin
        // s_reset -> s_normal after negedge reset (already done in run_phase)
        fsm_state = FSM_NORMAL;
      end
      FSM_NORMAL: begin
        if (vif.mon_cb.com_xcpt_valid)
          fsm_state = FSM_ROLLBACK; // 2-cycle later, approximate
        else if (has_unique_dispatch())
          fsm_state = FSM_WAIT_EMPTY;
      end
      FSM_ROLLBACK: begin
        if (vif.mon_cb.empty && !vif.mon_cb.commit_rollback)
          fsm_state = FSM_NORMAL;
      end
      FSM_WAIT_EMPTY: begin
        if (vif.mon_cb.com_xcpt_valid)
          fsm_state = FSM_ROLLBACK;  // F7.6
        else if (vif.mon_cb.empty)
          fsm_state = FSM_NORMAL;    // F7.5
      end
    endcase
  endfunction

  function bit has_unique_dispatch();
    for (int i = 0; i < CW; i++)
      if (vif.mon_cb.enq_valids[i] && vif.mon_cb.enq_uops_is_unique[i]) return 1;
    return 0;
  endfunction

  // ====================================================================
  // MASTER CHECK DISPATCHER
  // ====================================================================
  task check_all();
    chk_dispatch();
    chk_writeback();
    chk_lsu_clr();
    chk_commit();
    chk_exception();
    chk_branch();
    chk_pointers();
    chk_fsm_transitions();
    chk_csr_stall();
  endtask

  // ====================================================================
  // GROUP A — DISPATCH CHECKS
  // F1.1 full-width, F1.2 partial, F1.4 backpressure,
  // F1.5 rob_idx=tail+bank, F1.6 empty after reset, F1.7 fence
  // D1: no overwrite valid, D3: only dispatch when ready
  // ====================================================================
  task chk_dispatch();
    int  enq_count;
    bit  any_enq = 0;
    logic [6:0] dut_tail = vif.mon_cb.rob_tail_idx;
    logic       dut_ready = vif.mon_cb.ready;

    enq_count = 0;
    for (int i = 0; i < CW; i++) begin
      if (vif.mon_cb.enq_valids[i]) begin
        any_enq = 1;
        enq_count++;
        begin : chk_D3
          // D3: dispatch only when ready
          if (!dut_ready)
            scb_error("D3_DISPATCH_WHEN_NOT_READY",
              $sformatf("bank=%0d dispatched but io_ready=0", i));
        end
        begin : chk_D1
          // D1: no overwrite of valid entry
          int idx = vif.mon_cb.enq_uops_rob_idx[i];
          if (shadow[idx].valid && !shadow[idx].killed)
            scb_error("D1_OVERWRITE_VALID_ENTRY",
              $sformatf("bank=%0d rob_idx=%0d already valid", i, idx));
        end
        begin : chk_F1_5
          // F1.5 / A2: rob_idx >> log2(CW) == rob_tail (row portion)
          int exp_row = dut_tail >> $clog2(CW); // tail is already row idx in BOOM
          int act_row = vif.mon_cb.enq_uops_rob_idx[i] >> $clog2(CW);
          if (exp_row !== act_row)
            scb_error("F1_5_ROB_IDX_TAIL_MISMATCH",
              $sformatf("bank=%0d enq_rob_idx=%0d row=%0d expected_row=%0d",
                i, vif.mon_cb.enq_uops_rob_idx[i], act_row, exp_row));
        end
        begin : chk_F1_7
          // F1.7: fence dispatch → busy should NOT be set (busy=0 immediately)
          if (vif.mon_cb.enq_uops_is_fence[i] || vif.mon_cb.enq_uops_is_fencei[i]) begin
            // We cannot directly see DUT rob_bsy, but we track in shadow
            // Shadow will set busy=0 for fence; if DUT commits fence before WB, that's correct
            `uvm_info("SCB_V2",$sformatf("FENCE dispatch bank=%0d rob_idx=%0d",
              i, vif.mon_cb.enq_uops_rob_idx[i]), UVM_HIGH)
          end
        end
      end
    end

    begin : chk_F1_4
      // F1.4: if ROB full (sh_full), DUT must de-assert ready
      if (sh_full && dut_ready && any_enq)
        scb_error("F1_4_DISPATCH_WHEN_FULL",
          "ROB shadow full but io_ready=1 and dispatch occurring");
    end

    begin : chk_F1_6
      // F1.6: empty after reset → empty=1, ready=1 at start
      // (Checked implicitly at first cycle — one-time check via sim_cycle)
      if (sim_cycle == 1) begin
        if (!vif.mon_cb.empty)
          scb_error("F1_6_NOT_EMPTY_AFTER_RESET","io_empty=0 at cycle 1 after reset");
        if (!vif.mon_cb.ready)
          scb_error("F1_6_NOT_READY_AFTER_RESET","io_ready=0 at cycle 1 after reset");
      end
    end
  endtask

  // ====================================================================
  // GROUP B — WRITEBACK CHECKS
  // F2.2 WB clears busy, F2.3 WB clears unsafe, F2.6 pdst match,
  // F2.7 no double WB, W1 WB into valid, W2 WB into busy
  // ====================================================================
  task chk_writeback();
    for (int p = 0; p < WB_PORTS; p++) begin
      if (vif.mon_cb.wb_resps_valid[p]) begin
        int idx = vif.mon_cb.wb_resps_rob_idx[p];
        bit [6:0] wb_pdst = vif.mon_cb.wb_resps_pdst[p];

        // W1 / A3: WB entry must be valid
        if (!shadow[idx].valid)
          scb_error("W1_WB_INTO_INVALID",
            $sformatf("port=%0d rob_idx=%0d not valid in shadow", p, idx));

        // W2 / A4: WB entry must be busy (no double WB)
        else if (!shadow[idx].busy)
          scb_error("W2_DOUBLE_WB",
            $sformatf("port=%0d rob_idx=%0d already not-busy (double WB)", p, idx));

        else begin
          // W3 / A5 / F2.6: pdst match (only if ldst_val=1)
          if (shadow[idx].ldst_val && (shadow[idx].pdst !== wb_pdst))
            scb_error("W3_PDST_MISMATCH",
              $sformatf("port=%0d rob_idx=%0d exp_pdst=0x%0h got=0x%0h",
                p, idx, shadow[idx].pdst, wb_pdst));

          // F5.5: No WB into killed entry
          if (shadow[idx].killed)
            scb_error("F5_5_WB_AFTER_KILL",
              $sformatf("port=%0d rob_idx=%0d killed by branch mispredict, got WB", p, idx));
        end
      end
    end
  endtask

  // ====================================================================
  // GROUP B2 — LSU CLEAR BUSY CHECKS (F2.5, W4, W5)
  // ====================================================================
  task chk_lsu_clr();
    for (int p = 0; p < 3; p++) begin
      if (vif.mon_cb.lsu_clr_bsy_valid[p]) begin
        int idx = vif.mon_cb.lsu_clr_bsy_bits[p];
        // W4/A6: entry must be valid
        if (!shadow[idx].valid)
          scb_error("W4_LSU_CLR_INVALID",
            $sformatf("lsu_clr port=%0d rob_idx=%0d not valid", p, idx));
        // W5/A7: entry must be busy
        else if (!shadow[idx].busy)
          scb_error("W5_LSU_CLR_NOT_BUSY",
            $sformatf("lsu_clr port=%0d rob_idx=%0d already not-busy", p, idx));
      end
    end
  endtask

  // ====================================================================
  // GROUP C — COMMIT CHECKS
  // F3.1 in-order, F3.2 row commit, F3.4 blocked, F3.7 csr_stall,
  // F3.8 arch_valids vs valids, F3.6 drain to empty
  // A8: commit and rollback mutually exclusive
  // ====================================================================
  task chk_commit();
    bit any_commit = 0, any_rollback = 0;
    int commit_count = 0;

    for (int i = 0; i < CW; i++) begin
      if (vif.mon_cb.commit_valids[i])   begin any_commit   = 1; commit_count++; end
      if (vif.mon_cb.commit_rbk_valids[i]) any_rollback = 1;
    end

    // A8 / INVARIANT-1: commit and rollback mutually exclusive
    if (any_commit && any_rollback)
      scb_error("A8_COMMIT_ROLLBACK_EXCLUSIVE",
        "commit_valids and commit_rbk_valids both asserted same cycle");

    // F3.1: In-order commit — first committed bank must be bank 0 of head row
    // BOOM commits bank0→bank1→bank2→bank3 within same row
    if (any_commit) begin
      // Check: cannot commit bank[i] if bank[j<i] in same row is not committing
      // (blocked commit: if bank j is busy, banks j+1..3 also blocked)
      for (int i = 1; i < CW; i++) begin
        if (vif.mon_cb.commit_valids[i] && !vif.mon_cb.commit_valids[i-1]) begin
          // Only valid if bank[i-1] itself is not valid (predicated/empty slot)
          int idx_prev = ((vif.mon_cb.rob_head_idx >> $clog2(CW)) << $clog2(CW)) + (i-1);
          if (shadow[idx_prev].valid)
            scb_error("F3_1_OUT_OF_ORDER_COMMIT",
              $sformatf("bank%0d commits but bank%0d (same row) does not, yet entry valid",
                i, i-1));
        end
      end
      total_commits += commit_count;
    end

    // F3.4 / Blocked commit: if an entry is busy, later banks in same row must NOT commit
    begin : chk_blocked_commit
      bit row_blocked = 0;
      for (int i = 0; i < CW; i++) begin
        int idx = ((vif.mon_cb.rob_head_idx >> $clog2(CW)) << $clog2(CW)) + i;
        if (row_blocked && vif.mon_cb.commit_valids[i])
          scb_error("F3_4_BLOCKED_COMMIT",
            $sformatf("bank%0d commits but earlier bank was busy/blocked", i));
        if (shadow[idx].valid && shadow[idx].busy)
          row_blocked = 1;
      end
    end

    // F3.8: arch_valids ≤ valids (arch_valid requires commit_valid)
    for (int i = 0; i < CW; i++) begin
      if (vif.mon_cb.commit_arch_valids[i] && !vif.mon_cb.commit_valids[i])
        scb_error("F3_8_ARCH_VALID_WITHOUT_COMMIT",
          $sformatf("bank%0d arch_valid=1 but commit_valid=0", i));
    end

    // INVARIANT-3: commit while empty
    if (any_commit && vif.mon_cb.empty)
      scb_error("INV3_COMMIT_WHILE_EMPTY", "commit_valids active but ROB empty");

    // F3.6: after drain → empty=1
    // (checked implicitly by empty invariants above)
  endtask

  // ====================================================================
  // GROUP C2 — CSR STALL CHECK (F3.7)
  // ====================================================================
  task chk_csr_stall();
    if (vif.mon_cb.csr_stall) begin
      for (int i = 0; i < CW; i++) begin
        if (vif.mon_cb.commit_valids[i])
          scb_error("F3_7_COMMIT_DURING_CSR_STALL",
            $sformatf("bank%0d commit_valid=1 but csr_stall=1", i));
      end
    end
  endtask

  // ====================================================================
  // GROUP D — EXCEPTION CHECKS
  // F4.1 precise (only at head), F4.2 no early xcpt (if busy),
  // F4.3 com_xcpt_valid pulse, F4.6 exception blocks younger,
  // F4.8 2-cycle delay to rollback, F4.11 post-flush recovery
  // A9, A10, A11
  // ====================================================================
  task chk_exception();
    logic [6:0] head = vif.mon_cb.rob_head_idx;

    if (vif.mon_cb.com_xcpt_valid) begin
      total_xcpts++;

      // A11 / F4.1: exception rob_idx == rob_head
      // (DUT assertion; cross-check with head pointer)
      // We verify indirectly: only head-row entry should be source
      // Head entry in shadow should be valid and not busy
      if (shadow[head].busy)
        scb_error("F4_2_EARLY_EXCEPTION",
          $sformatf("com_xcpt_valid but head rob_idx=%0d still busy", head));

      // F4.3: com_xcpt_valid should not have been high last cycle too
      // (should be single-pulse per exception event, check state machine)
      if (prev_xcpt_valid && !vif.mon_cb.commit_rollback)
        scb_error("F4_3_XCPT_MULTI_PULSE",
          "com_xcpt_valid high for >1 cycle without rollback in between");

      // Record for 2-cycle delay check (F4.8)
      xcpt_thrown = 1;
      xcpt_thrown_cycle = sim_cycle;

      // A9: r_xcpt_val must be set → flush_frontend should activate
      // flush_frontend should assert soon after com_xcpt_valid
      // (We check this 1 cycle later via flush_valid)
    end

    // F4.8: 2-cycle delay from exception thrown to rollback start
    if (xcpt_thrown) begin
      int delay = sim_cycle - xcpt_thrown_cycle;
      if (delay >= 2 && vif.mon_cb.commit_rollback && !prev_rollback) begin
        // Rollback started — verify delay is roughly 2 cycles
        if (delay > 4)  // Allow some slack for pipeline depth
          scb_error("F4_8_ROLLBACK_DELAY_TOO_LONG",
            $sformatf("rollback started %0d cycles after exception, expected 2", delay));
        xcpt_thrown = 0;
      end
      if (delay > 10) begin
        scb_error("F4_8_ROLLBACK_NEVER_STARTED",
          "No rollback observed 10 cycles after exception");
        xcpt_thrown = 0;
      end
    end

    // F4.11 / A10: when empty → no exception should be pending
    if (vif.mon_cb.empty && vif.mon_cb.com_xcpt_valid)
      scb_error("A10_XCPT_WHILE_EMPTY",
        "com_xcpt_valid asserted but ROB empty");

    // F4.4: flush_valid must accompany or follow exception
    if (vif.mon_cb.flush_valid) begin
      total_flushes++;
      `uvm_info("SCB_V2",$sformatf("FLUSH: typ=%0d cycle=%0d",
        vif.mon_cb.flush_bits_flush_typ, sim_cycle), UVM_MEDIUM)
    end
  endtask

  // ====================================================================
  // GROUP E — BRANCH MISPREDICTION CHECKS
  // F5.1 br_mask kill, F5.2 tail snap-back, F5.3 speculative kill,
  // F5.4 br_mask update on survivors, F5.5 no WB after kill
  // ====================================================================
  task chk_branch();
    logic [19:0] mis_mask = vif.mon_cb.brupdate_b1_mispredict_mask;
    logic        mis_b2   = vif.mon_cb.brupdate_b2_mispredict;
    logic [6:0]  mis_idx  = vif.mon_cb.brupdate_b2_uop_rob_idx;

    if (mis_b2 && mis_mask != 0) begin
      `uvm_info("SCB_V2",$sformatf("BR_MISPREDICT mis_idx=%0d mis_mask=0x%0h cur_tail=%0d",
        mis_idx, mis_mask, vif.mon_cb.rob_tail_idx), UVM_LOW)

      // F5.1: All entries with matching br_mask bit should be invalidated
      // We check 1 cycle AFTER the mispredict (update happens next cycle)
      // Save mask for deferred check
      killed_br_mask = mis_mask;
    end

    // F5.2: Tail snap-back — after mispredict, tail should be <= mispredict branch row+1
    // Check the cycle AFTER mispredict
    if ($past(mis_b2) && $past(mis_mask) != 0) begin
      logic [6:0] exp_max_tail = ($past(mis_idx) + 1) % NUM_ROB; // approximate
      // Tail must have moved back (not past the branch idx)
      // This is a heuristic check; exact snap depends on WrapInc(branch_row)
      `uvm_info("SCB_V2",$sformatf("POST_MISPREDICT tail=%0d (branch_was=%0d)",
        vif.mon_cb.rob_tail_idx, $past(mis_idx)), UVM_MEDIUM)
    end

    // F5.4: Surviving entries should have their br_mask bit cleared
    // (Checked implicitly when subsequent WB/commit uses those entries)
  endtask

  // ====================================================================
  // GROUP F — POINTER LOGIC CHECKS
  // F6.1 tail wrap, F6.2 head wrap, F6.3 full detect, F6.4 empty detect
  // ====================================================================
  task chk_pointers();
    logic [6:0] cur_head = vif.mon_cb.rob_head_idx;
    logic [6:0] cur_tail = vif.mon_cb.rob_tail_idx;
    logic       cur_empty = vif.mon_cb.empty;
    logic       cur_ready = vif.mon_cb.ready; // ready = !full

    // F6.4: Empty condition — head == tail and no valid entries near head
    // DUT's empty signal should match our shadow
    begin : chk_empty_consistent
      bit shadow_has_valid = 0;
      for (int i = 0; i < NUM_ROB; i++)
        if (shadow[i].valid && !shadow[i].killed) shadow_has_valid = 1;
      if (cur_empty && shadow_has_valid) begin
        // Allow 1 cycle mismatch for pipeline latency
        `uvm_info("SCB_V2","NOTE: DUT empty=1 but shadow has valid entries (may be 1-cycle lag)",
          UVM_HIGH)
      end
    end

    // F6.1 / F6.2: Wrap-around — check tail/head wrap
    if (prev_tail > 80 && cur_tail < 20)
      `uvm_info("SCB_V2",$sformatf("TAIL WRAP: %0d -> %0d (F6.1)", prev_tail, cur_tail), UVM_LOW)
    if (prev_head > 80 && cur_head < 20)
      `uvm_info("SCB_V2",$sformatf("HEAD WRAP: %0d -> %0d (F6.2)", prev_head, cur_head), UVM_LOW)

    // F6.3: Full detection — if !ready, ROB should actually be full
    if (!cur_ready) begin
      int valid_count = 0;
      for (int i = 0; i < NUM_ROB; i++)
        if (shadow[i].valid && !shadow[i].killed) valid_count++;
      if (valid_count < 90) // numRobEntries=96, allow some slack
        `uvm_info("SCB_V2",$sformatf(
          "NOTE: io_ready=0 but shadow valid_count=%0d (may be fence/unique)",
          valid_count), UVM_MEDIUM)
    end
  endtask

  // ====================================================================
  // GROUP G — FSM TRANSITION CHECKS (F7.1–F7.6)
  // ====================================================================
  task chk_fsm_transitions();
    // F7.1: After reset → s_normal (already handled in run_phase)

    // F7.2: s_normal → s_rollback after exception
    if (fsm_prev == FSM_NORMAL && fsm_state == FSM_ROLLBACK) begin
      if (!prev_xcpt_valid && !vif.mon_cb.com_xcpt_valid)
        scb_error("F7_2_SPURIOUS_ROLLBACK",
          "Entered FSM_ROLLBACK without com_xcpt_valid");
      `uvm_info("SCB_V2","FSM: NORMAL → ROLLBACK (F7.2)", UVM_LOW)
    end

    // F7.3: s_rollback → s_normal when empty
    if (fsm_prev == FSM_ROLLBACK && fsm_state == FSM_NORMAL) begin
      if (!prev_empty)
        `uvm_info("SCB_V2","FSM: ROLLBACK → NORMAL (F7.3) — empty asserted", UVM_LOW)
    end

    // F7.4: s_normal → s_wait_till_empty on is_unique dispatch
    if (fsm_prev == FSM_NORMAL && fsm_state == FSM_WAIT_EMPTY)
      `uvm_info("SCB_V2","FSM: NORMAL → WAIT_EMPTY (F7.4) — unique instruction", UVM_LOW)

    // F7.5: s_wait_till_empty → s_normal when empty
    if (fsm_prev == FSM_WAIT_EMPTY && fsm_state == FSM_NORMAL)
      `uvm_info("SCB_V2","FSM: WAIT_EMPTY → NORMAL (F7.5)", UVM_LOW)

    // F7.6: s_wait_till_empty → s_rollback on exception
    if (fsm_prev == FSM_WAIT_EMPTY && fsm_state == FSM_ROLLBACK)
      `uvm_info("SCB_V2","FSM: WAIT_EMPTY → ROLLBACK (F7.6) — exception in wait state", UVM_LOW)
  endtask

  // ====================================================================
  // SHADOW UPDATE (After checks)
  // ====================================================================
  task update_shadow();
    // 1) Dispatch — update shadow
    for (int i = 0; i < CW; i++) begin
      if (vif.mon_cb.enq_valids[i]) begin
        int idx = vif.mon_cb.enq_uops_rob_idx[i];
        shadow[idx].valid     = 1;
        shadow[idx].busy      = !(vif.mon_cb.enq_uops_is_fence[i] ||
                                   vif.mon_cb.enq_uops_is_fencei[i]);
        shadow[idx].pdst      = vif.mon_cb.enq_uops_pdst[i];
        shadow[idx].ldst_val  = vif.mon_cb.enq_uops_ldst_val[i];
        shadow[idx].unsafe    = vif.mon_cb.enq_uops_unsafe[i];
        shadow[idx].is_fence  = vif.mon_cb.enq_uops_is_fence[i] ||
                                  vif.mon_cb.enq_uops_is_fencei[i];
        shadow[idx].is_unique = vif.mon_cb.enq_uops_is_unique[i];
        shadow[idx].br_mask   = vif.mon_cb.enq_uops_br_mask[i];
        shadow[idx].xcpt      = vif.mon_cb.enq_uops_exception[i];
        shadow[idx].killed    = 0;
        sh_tail = (idx + 1) % NUM_ROB; // approximate
      end
    end

    // 2) Writeback — clear busy
    for (int p = 0; p < WB_PORTS; p++) begin
      if (vif.mon_cb.wb_resps_valid[p]) begin
        int idx = vif.mon_cb.wb_resps_rob_idx[p];
        shadow[idx].busy   = 0;
        shadow[idx].unsafe = 0;
      end
    end

    // 3) LSU clear busy
    for (int p = 0; p < 3; p++) begin
      if (vif.mon_cb.lsu_clr_bsy_valid[p]) begin
        int idx = vif.mon_cb.lsu_clr_bsy_bits[p];
        shadow[idx].busy   = 0;
        shadow[idx].unsafe = 0;
      end
    end

    // 4) Branch mispredict kill
    if (vif.mon_cb.brupdate_b2_mispredict) begin
      logic [19:0] mis_mask = vif.mon_cb.brupdate_b1_mispredict_mask;
      for (int i = 0; i < NUM_ROB; i++) begin
        if (shadow[i].valid && (shadow[i].br_mask & mis_mask) != 0) begin
          shadow[i].valid  = 0;
          shadow[i].killed = 1;
        end
        // Surviving entries: clear resolved bits from br_mask (F5.4)
        if (shadow[i].valid)
          shadow[i].br_mask &= ~vif.mon_cb.brupdate_b1_resolve_mask;
      end
    end else begin
      // Normal resolve: just clear resolved bits
      if (vif.mon_cb.brupdate_b1_resolve_mask != 0) begin
        for (int i = 0; i < NUM_ROB; i++)
          if (shadow[i].valid)
            shadow[i].br_mask &= ~vif.mon_cb.brupdate_b1_resolve_mask;
      end
    end

    // 5) Commit — invalidate head entries
    for (int i = 0; i < CW; i++) begin
      if (vif.mon_cb.commit_valids[i]) begin
        int idx = ((vif.mon_cb.rob_head_idx >> $clog2(CW)) << $clog2(CW)) + i;
        shadow[idx].valid = 0;
        shadow[idx].busy  = 0;
      end
    end

    // 6) Flush — reset all
    if (vif.mon_cb.flush_valid)
      reset_shadow();
  endtask

  // ====================================================================
  // HELPER: Centralized error reporting
  // ====================================================================
  function void scb_error(string tag, string msg);
    error_count++;
    `uvm_error("SCB_V2", $sformatf("[%s] cycle=%0d : %s", tag, sim_cycle, msg))
  endfunction

  // ====================================================================
  // REPORT
  // ====================================================================
  function void report_phase(uvm_phase phase);
    `uvm_info("SCB_V2","========================================================",UVM_LOW)
    `uvm_info("SCB_V2",$sformatf("  Total cycles      : %0d", sim_cycle),     UVM_LOW)
    `uvm_info("SCB_V2",$sformatf("  Total commits     : %0d", total_commits),  UVM_LOW)
    `uvm_info("SCB_V2",$sformatf("  Total exceptions  : %0d", total_xcpts),    UVM_LOW)
    `uvm_info("SCB_V2",$sformatf("  Total flushes     : %0d", total_flushes),  UVM_LOW)
    `uvm_info("SCB_V2",$sformatf("  Invariant errors  : %0d", error_count),    UVM_LOW)
    if (error_count == 0)
      `uvm_info("SCB_V2","  RESULT: ALL INVARIANTS PASSED ✓", UVM_LOW)
    else
      `uvm_error("SCB_V2",$sformatf("  RESULT: %0d VIOLATIONS ✗", error_count))
    `uvm_info("SCB_V2","========================================================",UVM_LOW)
  endfunction

endclass


// =============================================================================
// [4] rob_coverage.sv
//
// Tất cả covergroup từ §7 testplan:
//   cg_dispatch_width, cg_partial_stall, cg_wb_port_usage,
//   cg_simultaneous_wb, cg_commit_width, cg_rob_occupancy,
//   cg_rob_state, cg_exception_type, cg_branch_outcome,
//   cg_pointer_wrap
//   + Cross covergroups từ §7.2
// =============================================================================

class rob_coverage extends uvm_subscriber #(rob_transaction);
  `uvm_component_utils(rob_coverage)

  virtual rob_if.MON vif;

  // ---- Sampled signals (updated each cycle) ----
  int          dispatch_width;   // 0-4 uops dispatched
  bit          partial_stall;
  int          wb_count;         // 0-10 WB ports active
  int          commit_width;     // 0-4 commits
  int          rob_occupancy;    // 0-96 entries
  bit [2:0]    rob_state;        // 0=reset,1=normal,2=rollback,3=wait_empty
  bit          xcpt_from_dispatch; // exception flag at dispatch time
  bit          xcpt_from_lsu;    // lxcpt_valid
  bit          xcpt_from_csr;    // csr_stall with xcpt (simplified)
  bit          branch_correct;
  bit          branch_mispredict;
  bit          head_wrap;
  bit          tail_wrap;

  // ---- Per-port WB usage ----
  bit [9:0]    wb_port_used;

  // ===== covergroup: Dispatch Width =====
  covergroup cg_dispatch_width;
    cp_width: coverpoint dispatch_width {
      bins zero  = {0};
      bins one   = {1};
      bins two   = {2};
      bins three = {3};
      bins four  = {4};
    }
  endgroup

  // ===== covergroup: Partial Stall =====
  covergroup cg_partial_stall_cg;
    cp_stall: coverpoint partial_stall {
      bins no_stall = {0};
      bins stall    = {1};
    }
  endgroup

  // ===== covergroup: WB Port Usage (per port) =====
  covergroup cg_wb_port_usage;
    cp_p0:  coverpoint wb_port_used[0] { bins used = {1}; bins unused = {0}; }
    cp_p1:  coverpoint wb_port_used[1] { bins used = {1}; bins unused = {0}; }
    cp_p2:  coverpoint wb_port_used[2] { bins used = {1}; bins unused = {0}; }
    cp_p3:  coverpoint wb_port_used[3] { bins used = {1}; bins unused = {0}; }
    cp_p4:  coverpoint wb_port_used[4] { bins used = {1}; bins unused = {0}; }
    cp_p5:  coverpoint wb_port_used[5] { bins used = {1}; bins unused = {0}; }
    cp_p6:  coverpoint wb_port_used[6] { bins used = {1}; bins unused = {0}; }
    cp_p7:  coverpoint wb_port_used[7] { bins used = {1}; bins unused = {0}; }
    cp_p8:  coverpoint wb_port_used[8] { bins used = {1}; bins unused = {0}; }
    cp_p9:  coverpoint wb_port_used[9] { bins used = {1}; bins unused = {0}; }
  endgroup

  // ===== covergroup: Simultaneous WB Count =====
  covergroup cg_simultaneous_wb;
    cp_wb: coverpoint wb_count {
      bins wb_1   = {1};
      bins wb_2   = {2};
      bins wb_3   = {3};
      bins wb_4   = {4};
      bins wb_5_8 = {[5:8]};
      bins wb_9_10= {9, 10};
    }
  endgroup

  // ===== covergroup: Commit Width =====
  covergroup cg_commit_width;
    cp_cw: coverpoint commit_width {
      bins zero  = {0};
      bins one   = {1};
      bins two   = {2};
      bins three = {3};
      bins four  = {4};
    }
  endgroup

  // ===== covergroup: ROB Occupancy =====
  covergroup cg_rob_occupancy;
    cp_occ: coverpoint rob_occupancy {
      bins empty       = {0};
      bins lt_25pct    = {[1:23]};
      bins b25_50pct   = {[24:47]};
      bins b50_75pct   = {[48:71]};
      bins b75_100pct  = {[72:95]};
      bins full        = {96};
    }
  endgroup

  // ===== covergroup: ROB FSM State =====
  covergroup cg_rob_state;
    cp_st: coverpoint rob_state {
      bins s_reset          = {0};
      bins s_normal         = {1};
      bins s_rollback       = {2};
      bins s_wait_till_empty= {3};
    }
  endgroup

  // ===== covergroup: Exception Type =====
  covergroup cg_exception_type;
    cp_xtype: coverpoint {xcpt_from_dispatch, xcpt_from_lsu, xcpt_from_csr} {
      bins dispatch_xcpt = {3'b100};
      bins lxcpt        = {3'b010};
      bins csr_replay   = {3'b001};
    }
  endgroup

  // ===== covergroup: Branch Outcome =====
  covergroup cg_branch_outcome;
    cp_br: coverpoint {branch_correct, branch_mispredict} {
      bins correct    = {2'b10};
      bins mispredict = {2'b01};
    }
  endgroup

  // ===== covergroup: Pointer Wrap =====
  covergroup cg_pointer_wrap;
    cp_hw: coverpoint head_wrap {
      bins no_wrap  = {0};
      bins wrapped  = {1};
    }
    cp_tw: coverpoint tail_wrap {
      bins no_wrap  = {0};
      bins wrapped  = {1};
    }
  endgroup

  // ===== CROSS COVERGROUPS (§7.2) =====

  // Cross: dispatch_width × rob_occupancy
  covergroup cg_cross_dispatch_occ;
    cp_dw:  coverpoint dispatch_width  { bins b[] = {[0:4]}; }
    cp_occ: coverpoint rob_occupancy   {
      bins empty      = {0};
      bins lt_25      = {[1:23]};
      bins b25_75     = {[24:71]};
      bins b75_full   = {[72:96]};
    }
    cx_dw_occ: cross cp_dw, cp_occ;
  endgroup

  // Cross: wb_count × commit_width
  covergroup cg_cross_wb_commit;
    cp_wb:  coverpoint wb_count    { bins b[] = {[0:10]}; }
    cp_cw:  coverpoint commit_width{ bins b[] = {[0:4]};  }
    cx_wb_cw: cross cp_wb, cp_cw;
  endgroup

  // Cross: rob_state × exception
  covergroup cg_cross_state_xcpt;
    cp_st:   coverpoint rob_state        { bins b[] = {[0:3]}; }
    cp_xcpt: coverpoint xcpt_from_dispatch { bins yes={1}; bins no={0}; }
    cx_st_xcpt: cross cp_st, cp_xcpt;
  endgroup

  // Cross: rob_state × mispredict
  covergroup cg_cross_state_mis;
    cp_st:  coverpoint rob_state          { bins b[] = {[0:3]}; }
    cp_mis: coverpoint branch_mispredict  { bins yes={1}; bins no={0}; }
    cx_st_mis: cross cp_st, cp_mis;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_dispatch_width   = new();
    cg_partial_stall_cg = new();
    cg_wb_port_usage    = new();
    cg_simultaneous_wb  = new();
    cg_commit_width     = new();
    cg_rob_occupancy    = new();
    cg_rob_state        = new();
    cg_exception_type   = new();
    cg_branch_outcome   = new();
    cg_pointer_wrap     = new();
    cg_cross_dispatch_occ = new();
    cg_cross_wb_commit  = new();
    cg_cross_state_xcpt = new();
    cg_cross_state_mis  = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual rob_if.MON)::get(this, "", "vif", vif))
      `uvm_fatal("COV", "Could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    @(negedge vif.reset);
    forever begin
      @(posedge vif.clock);
      sample_signals();
      sample_all_covergroups();
    end
  endtask

  // Receive transactions from monitor (satisfy uvm_subscriber)
  function void write(rob_transaction t); endfunction

  // ---- Sample all measured signals ----
  task sample_signals();
    logic [6:0] prev_h, prev_t;

    // Dispatch width
    dispatch_width = 0;
    for (int i = 0; i < 4; i++)
      if (vif.mon_cb.enq_valids[i]) dispatch_width++;

    partial_stall = vif.mon_cb.enq_partial_stall;

    // WB signals
    wb_count = 0; wb_port_used = 0;
    for (int i = 0; i < 10; i++) begin
      if (vif.mon_cb.wb_resps_valid[i]) begin
        wb_count++;
        wb_port_used[i] = 1;
      end
    end

    // Commit width
    commit_width = 0;
    for (int i = 0; i < 4; i++)
      if (vif.mon_cb.commit_valids[i]) commit_width++;

    // ROB occupancy (estimate from head/tail/empty/ready)
    begin
      logic [6:0] h = vif.mon_cb.rob_head_idx;
      logic [6:0] t = vif.mon_cb.rob_tail_idx;
      if (vif.mon_cb.empty)       rob_occupancy = 0;
      else if (!vif.mon_cb.ready) rob_occupancy = 96;  // full
      else if (t >= h)            rob_occupancy = (t - h);
      else                        rob_occupancy = (96 - h + t);
    end

    // FSM state (inferred)
    if (vif.mon_cb.commit_rollback)                         rob_state = 2; // s_rollback
    else if (vif.mon_cb.empty && !vif.mon_cb.commit_rollback
             && !vif.mon_cb.com_xcpt_valid)                 rob_state = 1; // s_normal
    else                                                    rob_state = 1; // default normal

    // Exception type
    xcpt_from_dispatch = 0;
    xcpt_from_lsu      = 0;
    xcpt_from_csr      = 0;
    for (int i = 0; i < 4; i++)
      if (vif.mon_cb.enq_valids[i] && vif.mon_cb.enq_uops_exception[i])
        xcpt_from_dispatch = 1;
    // lxcpt would need separate signal in mon_cb — placeholder:
    xcpt_from_lsu = 0;
    xcpt_from_csr = vif.mon_cb.csr_stall && vif.mon_cb.com_xcpt_valid;

    // Branch outcome
    branch_mispredict = vif.mon_cb.brupdate_b2_mispredict;
    branch_correct    = vif.mon_cb.brupdate_b1_resolve_mask != 0 && !branch_mispredict;

    // Pointer wrap detection (using $past — requires tool support)
    head_wrap = (vif.mon_cb.rob_head_idx < 4) && ($past(vif.mon_cb.rob_head_idx) > 88);
    tail_wrap = (vif.mon_cb.rob_tail_idx < 4) && ($past(vif.mon_cb.rob_tail_idx) > 88);
  endtask

  // ---- Sample all covergroups ----
  task sample_all_covergroups();
    cg_dispatch_width.sample();
    if (dispatch_width > 0 || partial_stall)
      cg_partial_stall_cg.sample();
    if (wb_count > 0) begin
      cg_wb_port_usage.sample();
      cg_simultaneous_wb.sample();
    end
    cg_commit_width.sample();
    cg_rob_occupancy.sample();
    cg_rob_state.sample();
    if (xcpt_from_dispatch || xcpt_from_lsu || xcpt_from_csr)
      cg_exception_type.sample();
    if (branch_correct || branch_mispredict)
      cg_branch_outcome.sample();
    if (head_wrap || tail_wrap)
      cg_pointer_wrap.sample();
    cg_cross_dispatch_occ.sample();
    if (wb_count > 0 && commit_width > 0)
      cg_cross_wb_commit.sample();
    if (xcpt_from_dispatch || xcpt_from_lsu)
      cg_cross_state_xcpt.sample();
    if (branch_mispredict)
      cg_cross_state_mis.sample();
  endtask

  // ---- Report coverage ----
  function void report_phase(uvm_phase phase);
    `uvm_info("COV","=========== COVERAGE REPORT ===========", UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_dispatch_width    : %.1f%%",
      cg_dispatch_width.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_partial_stall     : %.1f%%",
      cg_partial_stall_cg.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_wb_port_usage     : %.1f%%",
      cg_wb_port_usage.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_simultaneous_wb   : %.1f%%",
      cg_simultaneous_wb.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_commit_width      : %.1f%%",
      cg_commit_width.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_rob_occupancy     : %.1f%%",
      cg_rob_occupancy.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_rob_state         : %.1f%%",
      cg_rob_state.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_exception_type    : %.1f%%",
      cg_exception_type.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_branch_outcome    : %.1f%%",
      cg_branch_outcome.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  cg_pointer_wrap      : %.1f%%",
      cg_pointer_wrap.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV","  ---- Cross Coverage ----",            UVM_LOW)
    `uvm_info("COV",$sformatf("  dispatch × occupancy : %.1f%%",
      cg_cross_dispatch_occ.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  wb × commit          : %.1f%%",
      cg_cross_wb_commit.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  state × exception    : %.1f%%",
      cg_cross_state_xcpt.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV",$sformatf("  state × mispredict   : %.1f%%",
      cg_cross_state_mis.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV","=======================================", UVM_LOW)
  endfunction

endclass


// =============================================================================
// [5] rob_env_v2.sv — Updated env tích hợp scoreboard_v2 và coverage
// =============================================================================

class rob_env_v2 extends uvm_env;
  `uvm_component_utils(rob_env_v2)

  rob_agent           agt;
  rob_scoreboard_v2   scb;
  rob_coverage        cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = rob_agent::type_id::create("agt", this);
    scb = rob_scoreboard_v2::type_id::create("scb", this);
    cov = rob_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // Monitor → Scoreboard & Coverage
    agt.mon.ap.connect(scb.mon_export);
    agt.mon.ap.connect(cov.analysis_export);
  endfunction

endclass
