library ieee;
use ieee.std_logic_1164.all;

library work;
use work.wishbone_types.all;

entity wb_buffer is
    port (clk     : in std_ulogic;
	  rst     : in std_ulogic;

	  wb_master_in  : in wishbone_master_out;
	  wb_master_out : out wishbone_slave_out;

	  wb_slave_out  : out wishbone_master_out;
	  wb_slave_in   : in wishbone_slave_out
	  );
end wb_buffer;

architecture rtl of wb_buffer is
    signal stash   : wishbone_master_out;
begin

    process(clk)

        function wb_valid(wb : wishbone_master_out) return boolean is
        begin
            return wb.cyc = '1' and wb.stb = '1';
        end function;

        variable stalled: boolean;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stash.cyc <= '0';
                wb_slave_out.cyc <= '0';
                wb_master_out.ack <= '0';
            else
                -- We consider a stall condition if we get a stall from
                -- downstream *and* we have a request in the downstream
                -- buffer. In any other case, we can forward a request.
                stalled := wb_slave_in.stall = '1' and wb_valid(wb_slave_out);

                -- Downstream stalled, stash if free and there's a request, stash it
                if stalled and stash.cyc = '0' and wb_valid(wb_master_in) then
                    stash <= wb_master_in;
                end if;

                -- Downstream not stalled
                if not stalled then
                    -- Stash full, send it & clear it
                    if stash.cyc = '1' then
                        wb_slave_out <= stash;
                        stash.cyc <= '0';
                    else
                        -- Forward request
                        wb_slave_out <= wb_master_in;
                    end if;
                end if;

                -- Upstream latch of acks & data
                wb_master_out.ack <= wb_slave_in.ack;
                wb_master_out.dat <= wb_slave_in.dat;
            end if;
        end if;
    end process;

    -- Stall the master when the stash is full
    wb_master_out.stall <= stash.cyc and wb_master_in.cyc  and wb_master_in.stb;
end rtl;
