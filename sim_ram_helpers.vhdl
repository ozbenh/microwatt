library ieee;
use ieee.std_logic_1164.all;

package sim_ram_helpers is
    generic (
        WIDTH : integer := 32
        );
    subtype data_t is std_ulogic_vector(WIDTH-1 downto 0);
    subtype sel_t  is std_ulogic_vector(WIDTH/8-1 downto 0);

    function ram_create(rows: integer) return integer;
    
    function ram_load_file(blk : integer; row: integer; filename: string) return integer;
    attribute foreign of ram_load_file : function is "VHPIDIRECT ram_load_file";

    procedure ram_read(blk: integer; row: integer; data: out data_t);
    attribute foreign of ram_read : procedure is "VHPIDIRECT ram_read";

    procedure ram_write(blk: integer; row: integer; data: data_t; sel: sel_t);
    attribute foreign of ram_write : procedure is "VHPIDIRECT ram_write";
end package;

package body sim_ram_helpers is
    function ram_create(rows: integer) return integer is
        function ram_create_internal(width: integer; size: integer) return integer;
        attribute foreign of ram_create_internal : function is "VHPIDIRECT ram_create";
        function ram_create_internal(width: integer; size: integer) return integer is
        begin
            assert false report "VHPI" severity failure;
        end;
    begin
        assert WIDTH mod 8 = 0 report "Only width multiple of 8 supported !" severity failure;
        return ram_create_internal(WIDTH/8, rows);
    end;

    
    function ram_load_file(blk : integer; row: integer; filename: string) return integer is
    begin
        assert false report "VHPI" severity failure;
    end function;

    procedure ram_read(blk: integer; row: integer; data: out data_t) is
    begin
        assert false report "VHPI" severity failure;
    end procedure;

    procedure ram_write(blk: integer; row: integer; data: data_t; sel: sel_t) is
    begin
        assert false report "VHPI" severity failure;
    end procedure;
end package body;
