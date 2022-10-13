-- -----------------------------------------------------------------------------
--
--  Title      :  Edge-Detection design project - task 2.
--             :
--  Developers :  YOUR NAME HERE - s??????@student.dtu.dk
--             :  YOUR NAME HERE - s??????@student.dtu.dk
--             :
--  Purpose    :  This design contains an entity for the accelerator that must be build
--             :  in task two of the Edge Detection design project. It contains an
--             :  architecture skeleton for the entity as well.
--             :
--  Revision   :  1.0   ??-??-??     Final version
--             :
--
-- -----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The entity for task two. Notice the additional signals for the memory.
-- reset is active high.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.types.all;

entity acc is
    generic (
        SELECT_WORD_COUNT : natural range 0 to 5 := 1
    );
    port(
        clk    : in  bit_t;             -- The clock.
        reset  : in  bit_t;             -- The reset signal. Active high.
        addr   : out halfword_t;        -- Address bus for data.
        dataR  : in  word_t;            -- The data bus.
        dataW  : out word_t;            -- The data bus.
        en     : out bit_t;             -- Request signal for data.
        we     : out bit_t;             -- Read/Write signal for data.
        start  : in  bit_t;
        finish : out bit_t
    );
end acc;

--------------------------------------------------------------------------------
-- The desription of the accelerator.
--------------------------------------------------------------------------------

architecture rtl of acc is

    -- Constants
    constant IMAGE_WIDTH        : natural := 352;
    constant IMAGE_HEIGHT       : natural := 288;
    constant BITS_PER_PIXEL     : natural := 8;
    constant PIXELS_PER_WORD    : natural := (halfword_t'high)/BITS_PER_PIXEL;
    constant BUFFER_WIDTH       : natural := 2*IMAGE_WIDTH+2*PIXELS_PER_WORD;
    constant TOTAL_PIXELS       : natural := IMAGE_WIDTH*IMAGE_HEIGHT;
    constant TOTAL_WORDS        : natural := TOTAL_PIXELS/PIXELS_PER_WORD;

    -- Image signals
    signal siColumnSelect : integer := IMAGE_WIDTH/(BUFFER_WIDTH);
    
    -- FSM signals
    type state_t is (stRead, stWrite);
    attribute enum_encoding : string;
    attribute enum_encoding of state_t : type is "one-hot";
    signal sstState, sstNextState : state_t := stRead;

    -- Buffer signals
    --type internalBufferRow_t is array (0 to BUFFER_WIDTH - 1) of unsigned(7 downto 0);
    --type internalBuffer_t is array (0 to 2) of internalBufferRow_t;
    --signal sau3Buffer : internalBuffer_t := (others => (others => '0'));
    --signal siBufferRowSelect : integer range 0 to 2 := 0;
    --signal siBufferColumnSelect : integer range 0 to BUFFER_WIDTH - 1 := 0;
    type internalBuffer_t is array (0 to BUFFER_WIDTH) of byte_t;
    signal sauBuffer   : internalBuffer_t := (others => (others => '0'));
    signal siAddrRead  : natural range 0 to TOTAL_WORDS - 1 + BUFFER_WIDTH := 0;
    signal siAddrWrite : natural range 0 to TOTAL_WORDS - 1 := 0;
    -- Memory signals
    signal siMemAddrRead : halfword_t := halfword_zero;
begin

-- Template for a process

    FSM_logic : process(clk)
    begin
        case(sstState) is

            when stRead =>
                
            when stWrite =>
                
        
            when others =>
        
        end case ;
    end process FSM_logic;

    FSM_mem : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sstState <= stRead;
            else
                sstState <= sstNextState;
            end if;
        end if;
    end process FSM_mem;

end rtl;
