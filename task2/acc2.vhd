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
    constant PIXELS_PER_WORD        : natural := (word_t'length)/BITS_PER_PIXEL;
    constant BUFFER_WIDTH           : natural := (2*IMAGE_WIDTH) + (2*PIXELS_PER_WORD);
    constant TOTAL_PIXELS           : natural := (IMAGE_WIDTH * IMAGE_HEIGHT);
    constant TOTAL_WORDS            : natural := (TOTAL_PIXELS / PIXELS_PER_WORD);
    constant TOTAL_MEM_ADDR         : natural := (TOTAL_WORDS * 2);

    constant COUNTER_LEAD           : natural := IMAGE_WIDTH/PIXELS_PER_WORD + (2);

    -- Image signals
    signal siWriteCount, siNextWriteCount : integer range 0 to TOTAL_WORDS := 0;
    signal siReadCount, siNextReadCount : integer range 0 to TOTAL_WORDS := 0;
    
    -- FSM signals
    type state_t is (stIdle, stRead, stWrite, stReset, stDone);
    signal sstState, sstNextState : state_t := stIdle;
    signal siAddress, siNextAddress : integer range 0 to TOTAL_MEM_ADDR - 1 := 0; 

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
begin
    -- Combinatorial circuit
    -- Combinatorial circuit process definitions
    process (siAddress)
    begin
        addr <= std_logic_vector(to_unsigned(siAddress, addr'length));
    end process;

    dataW <= std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(sauResultBuffer'length - 3))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(sauResultBuffer'length - 2))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(sauResultBuffer'length - 1))) & std_logic_vector(unsigned(byte_one) - unsigned(sauImageBuffer(IMAGE_WIDTH + 2*PIXELS_PER_WORD)));

    FSM_logic : process(sstState, siWriteCount, siReadCount, siAddress, sauImageBuffer, sauResultBuffer, start, dataR)
        
        procedure pSetNextValues(nextState : in state_t;
                                incrementCounter : in std_logic;
                                nextAddress : in integer range 0 to (TOTAL_WORDS * 2) - 1;
                                enable : in std_logic;
                                writeEnable : in std_logic) is
        begin
            sstNextState <= nextState;
            siNextAddress <= nextAddress;
        
            sauNextImageBuffer <= sauImageBuffer;
            sauNextResultBuffer <= sauResultBuffer;

            siNextWriteCount <= siWriteCount;
            siNextReadCount <= siReadCount;

            en <= enable;
            if incrementCounter = '1' then
                
                if siWriteCount < TOTAL_WORDS and siReadCount > COUNTER_LEAD - 1 then
                    siNextWriteCount <= siWriteCount + 1;
                    we <= writeEnable;
                end if;

                if siReadCount <= TOTAL_WORDS - 1 then
                    siNextReadCount <= siReadCount + 1;
                end if;
                if siWriteCount = TOTAL_WORDS then
                    sstNextState <= stDone;
                    finish <= '1';
                end if;
            else
                we <= '0';
            end if;
        end procedure;
    begin
        finish <= '0';
        pSetNextValues(stIdle, '0', 0, '0', '0');
        case(sstState) is
            when stIdle =>
            
                pSetNextValues(stIdle, '0', 0, '0', '0');
                finish <= '0';
                if start = '1' then
                    sstNextState <= stRead;
                end if;

            when stRead =>
                pSetNextValues(stWrite, '0', siWriteCount + TOTAL_WORDS, '1', '0');
            when stWrite =>
                pSetNextValues(stRead, '1', siReadCount, '1', '1');
                sauNextImageBuffer <= sauImageBuffer(4 to sauImageBuffer'length - 1) & dataR(dataR'length - (1) downto dataR'length - (BITS_PER_PIXEL)) & dataR(dataR'length - (1 + BITS_PER_PIXEL) downto dataR'length - (BITS_PER_PIXEL*2)) & dataR(dataR'length - (1 + BITS_PER_PIXEL*2) downto dataR'length - (BITS_PER_PIXEL*3)) & dataR(dataR'length - (1 + BITS_PER_PIXEL*3) downto dataR'length - (BITS_PER_PIXEL*4));
                if siReadCount > COUNTER_LEAD - 2 then
                    sauNextResultBuffer <= sauResultBuffer(4 to sauNextResultBuffer'length - 1) & sauImageBuffer(IMAGE_WIDTH + PIXELS_PER_WORD*2) & sauImageBuffer(IMAGE_WIDTH + PIXELS_PER_WORD*2 + 1) & sauImageBuffer(IMAGE_WIDTH + PIXELS_PER_WORD*2 + 2) & sauImageBuffer(IMAGE_WIDTH + PIXELS_PER_WORD*2 + 3);
                end if;

            when stDone =>

                finish <= '1';
                if start = '0' then
                    sstNextState <= stIdle;
                end if;

            when others =>
            sstNextState <= stIdle;
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

                sauImageBuffer <= (others => (others => '0'));
                sauResultBuffer <= (others => (others => '0'));
            else
                sstState <= sstNextState;
                siWriteCount <= siNextWriteCount;
                siReadCount <= siNextReadCount;
                siAddress <= siNextAddress;

                sauImageBuffer <= sauNextImageBuffer;
                sauResultBuffer <= sauNextResultBuffer;
            end if;
        end if;
    end process FSM_mem;

end rtl;
