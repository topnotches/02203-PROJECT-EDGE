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
    constant IMAGE_WIDTH            : natural := 352;
    constant IMAGE_HEIGHT           : natural := 288;
    constant BITS_PER_PIXEL         : natural := 8;
    constant BUFFER_WIDTH_RESULT    : natural := 7;
    constant PIXELS_PER_WORD        : natural := (word_t'high)/BITS_PER_PIXEL;
    constant BUFFER_WIDTH           : natural := (2*IMAGE_WIDTH) + (2*PIXELS_PER_WORD);
    constant TOTAL_PIXELS           : natural := (IMAGE_WIDTH * IMAGE_HEIGHT);
    constant TOTAL_WORDS            : natural := (TOTAL_PIXELS / PIXELS_PER_WORD);
    constant TOTAL_MEM_ADDR         : natural := (TOTAL_WORDS * 2);

    constant COUNTER_LEAD           : natural := IMAGE_WIDTH + (2*PIXELS_PER_WORD);

    -- Image signals
    signal siWriteCount, siNextWriteCount : integer range 0 to TOTAL_WORDS := 0;
    signal siReadCount, siNextReadCount : integer range 0 to TOTAL_WORDS := 0;
    
    -- FSM signals
    type state_t is (stIdle, stRead, stWrite);
    attribute enum_encoding : string;
    attribute enum_encoding of state_t : type is "one-hot";
    signal sstState, sstNextState : state_t := stRead;
    signal siAddress, siNextAddress : integer range 0 to TOTAL_WORDS - 1 := 0; 

    -- Buffer signals
    --type internalBufferRow_t is array (0 to BUFFER_WIDTH - 1) of unsigned(7 downto 0);
    --type imageBuffer_t is array (0 to 2) of internalBufferRow_t;
    --signal sau3Buffer : imageBuffer_t := (others => (others => '0'));
    --signal siBufferRowSelect : integer range 0 to 2 := 0;
    --signal siBufferColumnSelect : integer range 0 to BUFFER_WIDTH - 1 := 0;
    type imageBuffer_t is array (0 to BUFFER_WIDTH) of byte_t;
    signal sauImageBuffer, sauNextImageBuffer   : imageBuffer_t := (others => (others => '0'));
    type resultBuffer_t is array (0 to BUFFER_WIDTH_RESULT) of byte_t;
    signal sauResultBuffer, sauNextResultBuffer   : resultBuffer_t := (others => (others => '0'));
    -- signal siAddressRead  : natural range 0 to TOTAL_WORDS - 1 + BUFFER_WIDTH := 0;
    -- signal siAddressWrite : natural range 0 to TOTAL_WORDS - 1 := 0;
    -- Memory signals

    procedure pSetNextValues(nextState : in state_t;
                            incrementCounter : in std_logic;
                            nextAddress : in integer range 0 to (TOTAL_WORDS * 2) - 1;
                            enable : in std_logic) is
    begin
        sstNextState <= nextState;
        siNextAddress <= to_unsigned(nextAddress, addr'length);
    
        sauNextImageBuffer <= sauImageBuffer;
        sauNextResultBuffer <= sauResultBuffer;

        siNextWriteCount <= siWriteCount;
        siNextReadCount <= siReadCount;

        en <= enable;
        if incrementCounter = '1' then
            
            sauNextImageBuffer <= sauImageBuffer;
            sauNextResultBuffer <= sauResultBuffer;

            if siWriteCount /= TOTAL_WORDS and siReadCount >= COUNTER_LEAD - 1 then
                siNextWriteCount <= siWriteCount + 1;
            end if;

            if siReadCount /= TOTAL_WORDS then
                siNextReadCount <= siReadCount + 1;
            end if;

        end if;
    end procedure;

begin
    -- Combinatorial circuit
    -- Combinatorial circuit process definitions
    process (siReadCount, siWriteCount)
    begin
        addr <= to_unsigned(siAddress, dataR'length);
    end process;



    FSM_logic : process(sstState, siWriteCount, siReadCount, siAddress)
    
    begin
        finish <= '0';
        case(sstState) is
            when stIdle =>
            
                pSetNextValues(stIdle, '0', (others => '0') , '0');
                finish <= '1';
                if start = '1' then
                    sstNextState <= stRead;
                end if;

            when stRead =>
                pSetNextValues(stWrite, '0', siWriteCount + TOTAL_WORDS, '1');

            when stWrite =>
                pSetNextValues(stRead, '1', siReadCount, '1');

            when others =>
        
        end case ;
    end process FSM_logic;

    FSM_mem : process(clk, reset)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                sstState <= stIdle;
                siWriteCount <= 0;
                siReadCount <= 0;
                siAddress <= 0;
            else
                sstState <= sstNextState;
                siWriteCount <= siNextWriteCount;
                siReadCount <= siNextReadCount;
                siAddress <= siNextAddress;
            end if;
        end if;
    end process FSM_mem;

end rtl;
