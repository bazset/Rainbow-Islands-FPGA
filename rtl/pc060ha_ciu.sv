module pc060ha_ciu
(
	input        clk,
	input        reset,
	input        m_port_cs,
	input        m_comm_cs,
	input        m_wr,
	input        m_rd,
	input  [7:0] m_din,
	output [7:0] m_dout,
	input        s_port_cs,
	input        s_comm_cs,
	input        s_wr,
	input        s_rd,
	input  [7:0] s_din,
	output [7:0] s_dout,
	output       slave_nmi,
	output       slave_reset,
	output reg       cmd_stb,
	output reg [7:0] cmd_byte
);

reg [3:0] mainmode, submode;
reg [3:0] status;
reg       nmi_enabled;
reg       slave_reset_r;
reg [3:0] slavedata  [0:3];
reg [3:0] masterdata [0:3];
wire mp_w_lvl = m_port_cs & m_wr;
wire mc_w_lvl = m_comm_cs & m_wr;
wire mc_r_lvl = m_comm_cs & m_rd;
wire sp_w_lvl = s_port_cs & s_wr;
wire sc_w_lvl = s_comm_cs & s_wr;
wire sc_r_lvl = s_comm_cs & s_rd;
reg mp_w_d, mc_w_d, mc_r_d, sp_w_d, sc_w_d, sc_r_d;
always @(posedge clk) begin
	mp_w_d <= mp_w_lvl;
	mc_w_d <= mc_w_lvl;
	mc_r_d <= mc_r_lvl;
	sp_w_d <= sp_w_lvl;
	sc_w_d <= sc_w_lvl;
	sc_r_d <= sc_r_lvl;
end

wire mp_w_strobe = ~mp_w_lvl & mp_w_d;
wire mc_w_strobe = ~mc_w_lvl & mc_w_d;
wire mc_r_strobe = ~mc_r_lvl & mc_r_d;
wire sp_w_strobe = ~sp_w_lvl & sp_w_d;
wire sc_w_strobe = ~sc_w_lvl & sc_w_d;
wire sc_r_strobe = ~sc_r_lvl & sc_r_d;
reg [3:0] mp_w_data, mc_w_data, sp_w_data, sc_w_data;
always @(posedge clk) begin
	if (mp_w_lvl) mp_w_data <= m_din[3:0];
	if (mc_w_lvl) mc_w_data <= m_din[3:0];
	if (sp_w_lvl) sp_w_data <= s_din[3:0];
	if (sc_w_lvl) sc_w_data <= s_din[3:0];
end

reg [7:0] m_dout_r, s_dout_r;
always_comb begin
	case (mainmode)
		4'd0:    m_dout_r = {4'h0, masterdata[0]};
		4'd1:    m_dout_r = {4'h0, masterdata[1]};
		4'd2:    m_dout_r = {4'h0, masterdata[2]};
		4'd3:    m_dout_r = {4'h0, masterdata[3]};
		4'd4:    m_dout_r = {4'h0, status};
		default: m_dout_r = 8'h00;
	endcase
end
assign m_dout = m_dout_r;
always_comb begin
	case (submode)
		4'd0:    s_dout_r = {4'h0, slavedata[0]};
		4'd1:    s_dout_r = {4'h0, slavedata[1]};
		4'd2:    s_dout_r = {4'h0, slavedata[2]};
		4'd3:    s_dout_r = {4'h0, slavedata[3]};
		4'd4:    s_dout_r = {4'h0, status};
		default: s_dout_r = 8'h00;
	endcase
end
assign s_dout = s_dout_r;

always @(posedge clk) begin
	if (reset) begin
		mainmode <= 4'd0;
		submode  <= 4'd0;
		status   <= 4'd0;
		nmi_enabled <= 1'b0;
		slave_reset_r <= 1'b0;
		slavedata[0] <= 4'd0; slavedata[1] <= 4'd0; slavedata[2] <= 4'd0; slavedata[3] <= 4'd0;
		masterdata[0] <= 4'd0; masterdata[1] <= 4'd0; masterdata[2] <= 4'd0; masterdata[3] <= 4'd0;
	end else begin

		if (mp_w_strobe) mainmode <= mp_w_data;
		if (mc_w_strobe) begin
			case (mainmode)
				4'd0: begin slavedata[0] <= mc_w_data; mainmode <= mainmode + 4'd1; end
				4'd1: begin slavedata[1] <= mc_w_data; mainmode <= mainmode + 4'd1; status[0] <= 1'b1; end
				4'd2: begin slavedata[2] <= mc_w_data; mainmode <= mainmode + 4'd1; end
				4'd3: begin slavedata[3] <= mc_w_data; mainmode <= mainmode + 4'd1; status[1] <= 1'b1; end
				4'd4: slave_reset_r <= (mc_w_data != 4'd0);
				default: ;
			endcase
		end

		if (mc_r_strobe) begin
			case (mainmode)
				4'd0: mainmode <= mainmode + 4'd1;
				4'd1: begin status[2] <= 1'b0; mainmode <= mainmode + 4'd1; end
				4'd2: mainmode <= mainmode + 4'd1;
				4'd3: begin status[3] <= 1'b0; mainmode <= mainmode + 4'd1; end
				default: ;
			endcase
		end

		if (sp_w_strobe) submode <= sp_w_data;
		if (sc_w_strobe) begin
			case (submode)
				4'd0: begin masterdata[0] <= sc_w_data; submode <= submode + 4'd1; end
				4'd1: begin masterdata[1] <= sc_w_data; submode <= submode + 4'd1; status[2] <= 1'b1; end
				4'd2: begin masterdata[2] <= sc_w_data; submode <= submode + 4'd1; end
				4'd3: begin masterdata[3] <= sc_w_data; submode <= submode + 4'd1; status[3] <= 1'b1; end
				4'd5: nmi_enabled <= 1'b0;
				4'd6: nmi_enabled <= 1'b1;
				default: ;
			endcase
		end

		if (sc_r_strobe) begin
			case (submode)
				4'd0: submode <= submode + 4'd1;
				4'd1: begin status[0] <= 1'b0; submode <= submode + 4'd1; end
				4'd2: submode <= submode + 4'd1;
				4'd3: begin status[1] <= 1'b0; submode <= submode + 4'd1; end
				default: ;
			endcase
		end
	end
end

assign slave_nmi   = nmi_enabled & (status[0] | status[1]);
assign slave_reset = slave_reset_r;

always @(posedge clk) begin
	cmd_stb <= 1'b0;
	if (reset) begin
		cmd_byte <= 8'd0;
	end else if (mc_w_strobe) begin
		if (mainmode == 4'd1) begin
			cmd_byte <= {mc_w_data, slavedata[0]};
			cmd_stb  <= 1'b1;
		end else if (mainmode == 4'd3) begin
			cmd_byte <= {mc_w_data, slavedata[2]};
			cmd_stb  <= 1'b1;
		end
	end
end

endmodule
