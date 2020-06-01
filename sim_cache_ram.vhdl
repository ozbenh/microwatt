library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity cache_ram is
    generic(
	ROW_BITS : integer := 16;
	WIDTH    : integer := 64;
	TRACE    : boolean := false;
	ADD_BUF  : boolean := false
	);

    port(
	clk     : in  std_logic;
	rd_en   : in  std_logic;
	rd_addr : in  std_logic_vector(ROW_BITS - 1 downto 0);
	rd_data : out std_logic_vector(WIDTH - 1 downto 0);
	wr_sel  : in  std_logic_vector(WIDTH/8 - 1 downto 0);
	wr_addr : in  std_logic_vector(ROW_BITS - 1 downto 0);
	wr_data : in  std_logic_vector(WIDTH - 1 downto 0)
	);

end cache_ram;

architecture sim of cache_ram is
    constant SIZE : integer := 2**ROW_BITS;

    package sim_ram is new work.sim_ram_helpers generic map (WIDTH => WIDTH);
    use sim_ram.all;

    signal blk : integer := ram_create(SIZE);
    signal rd_data0 : std_logic_vector(WIDTH - 1 downto 0);

begin
    process(clk)
	constant sel0 : std_logic_vector(WIDTH/8 - 1 downto 0) := (others => '0');
        variable dat  : std_ulogic_vector(WIDTH - 1 downto 0);
    begin
	if rising_edge(clk) then
            if wr_sel /= sel0 then
                if TRACE then
                    report "write a:" & to_hstring(wr_addr) &
                        " sel:" & to_hstring(wr_sel) &
                        " dat:" & to_hstring(wr_data);
                end if;
                ram_write(blk, to_integer(unsigned(wr_addr)), wr_data, wr_sel);
            end if;
	    if rd_en = '1' then
                ram_read(blk, to_integer(unsigned(rd_addr)), dat);
                rd_data0 <= dat;
		if TRACE then
		    report "read a:" & to_hstring(rd_addr) &
			" dat:" & to_hstring(dat);
		end if;
	    end if;
	end if;
    end process;

    buf: if ADD_BUF generate
    begin
	process(clk)
	begin
	    if rising_edge(clk) then
		rd_data <= rd_data0;
	    end if;
	end process;
    end generate;

    nobuf: if not ADD_BUF generate
    begin
	rd_data <= rd_data0;
    end generate;

end;
