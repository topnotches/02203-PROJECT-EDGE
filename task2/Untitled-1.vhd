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

entity acc23 is
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

architecture rtl of acc23 is

    -- Constants
    constant IMAGE_WIDTH            : natural := 352;
    constant IMAGE_HEIGHT           : natural := 288;
    constant BITS_PER_PIXEL         : natural := 8;
    constant BUFFER_WIDTH_RESULT    : natural := 7;
    constant PIXELS_PER_WORD        : natural := (word_t'length)/BITS_PER_PIXEL;
    constant BUFFER_SIZE            : natural := IMAGE_WIDTH;
    constant BUFFER_WORDS           : natural := BUFFER_SIZE/4;
    constant TOTAL_PIXELS           : natural := IMAGE_WIDTH * IMAGE_HEIGHT;
    constant TOTAL_WORDS            : natural := TOTAL_PIXELS / PIXELS_PER_WORD;
    constant TOTAL_WORDS_WIDTH      : natural := IMAGE_WIDTH/4;
    constant TOTAL_MEM_ADDR         : natural := TOTAL_WORDS * 2;
    constant TOTAL_BUFFER_ROWS      : natural := 3;

    constant COUNTER_LEAD           : natural := IMAGE_WIDTH/PIXELS_PER_WORD + (2);

    -- Image signals
    signal siWriteCount, siNextWriteCount : integer range 0 to TOTAL_WORDS := 0;
    signal siReadCount, siNextReadCount : integer range 0 to TOTAL_WORDS := 0;
    
    -- FSM signals
    type state_t is (stIdle, stRead, stWrite, stReset, stDone);
    signal sstState, sstNextState : state_t := stIdle;
    signal siAddress, siNextAddress : integer range 0 to TOTAL_MEM_ADDR - 1 := 0; 

    -- Buffer signals
    type imageBuffer_t is array (0 to BUFFER_WORDS - 1) of word_t;

    constant cauImageBufferInit : imageBuffer_t := (others => (others => '0'));
    signal sauImageBuffer0, sauImageBuffer1, sauImageBuffer2 : imageBuffer_t := cauImageBufferInit;
    attribute ram_style : string;
    attribute ram_style of sauImageBuffer : signal is "LUTRAM";

    constant clvSelectRowOrderInit : std_logic_vector(2 downto 0) := "010";
    signal slvSelectRowOrder, slvNextSelectRowOrder : std_logic_vector(2 downto 0) := clvSelectRowOrderInit;

    signal siSelectWord, siNextSelectWord : integer range 0 to TOTAL_WORDS_WIDTH - 1 := 0;
    signal siSelectRow : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    
    signal siRowOrder0  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal siRowOrder1  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal siRowOrder2  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    
    type resultBuffer_t is array (0 to BUFFER_WIDTH_RESULT) of byte_t;

    constant cauResultBuffer   : resultBuffer_t := (others => (others => '0'));
    signal sauResultBuffer, sauNextResultBuffer   : resultBuffer_t := cauResultBuffer;

    -- Port signals
begin
    


    -- Combinatorial circuit
    process (siAddress, slvSelectRowOrder, siRowOrder2)
    begin
        addr <= std_logic_vector(to_unsigned(siAddress, addr'length));
        
        siRowOrder0 <= to_integer(unsigned'(slvSelectRowOrder(2) & slvSelectRowOrder(0)));
        siRowOrder1 <= to_integer(unsigned'(slvSelectRowOrder(0) & slvSelectRowOrder(1)));
        siRowOrder2 <= to_integer(unsigned'(slvSelectRowOrder(1) & slvSelectRowOrder(2)));
        siSelectRow <= 2 - siRowOrder2;

    end process;

    dataW <= std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(0))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(1))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(2))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(3)));
    FSM_logic : process(sstState, siWriteCount, siReadCount, siAddress, sauImageBuffer, sauResultBuffer, start, dataR, slvSelectRowOrder, siSelectRow, siRowOrder0, siRowOrder1, siSelectWord)
        
        -- Next State Procedure 
        procedure pSetNextValues(nextState : in state_t;
                                incrementCounter : in std_logic;
                                nextAddress : in integer range 0 to (TOTAL_WORDS * 2);
                                enable : in std_logic;
                                writeEnable : in std_logic) is
        begin
            sstNextState <= nextState;
            siNextAddress <= nextAddress;
        
            sauNextImageBuffer <= sauImageBuffer;
            sauNextResultBuffer <= sauResultBuffer;

            siNextWriteCount <= siWriteCount;
            siNextReadCount <= siReadCount;

            siNextSelectWord <= siSelectWord;
            slvNextSelectRowOrder <= slvSelectRowOrder;

            en <= enable;
            if incrementCounter = '1' then
                
                if siWriteCount < TOTAL_WORDS and siReadCount > COUNTER_LEAD - 1 then
                    siNextWriteCount <= siWriteCount + 1;
                    we <= writeEnable;
                end if;

                if siReadCount < TOTAL_WORDS then
                    siNextReadCount <= siReadCount + 1;
                end if;

                if siSelectWord < TOTAL_WORDS_WIDTH - 1 then
                    siNextSelectWord <= siSelectWord + 1;  
                else
                    siNextSelectWord <= 0;
                    slvNextSelectRowOrder <= slvSelectRowOrder(1 downto 0) & slvSelectRowOrder(2);
                end if;

                if siWriteCount = TOTAL_WORDS - 1 then
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
                --sauNextImageBuffer <= sauImageBuffer(4 to sauImageBuffer'length - 1) &&  &  & ;
                
                sauImageBuffer(TOTAL_WORDS_WIDTH*siSelectRow + siSelectWord) <= dataR(dataR'length - (1) downto dataR'length - (BITS_PER_PIXEL));

                
                if siReadCount > COUNTER_LEAD - 2 then
                    if siSelectWord = 0 then
                        sauNextResultBuffer <= sauResultBuffer(4 to sauNextResultBuffer'length - 1) & sauImageBuffer(IMAGE_WIDTH*siRowOrder0 + sauImageBuffer(siRowOrder0)'length - 1) & sauImageBuffer(IMAGE_WIDTH*siRowOrder1 + PIXELS_PER_WORD*siSelectWord) & sauImageBuffer(IMAGE_WIDTH*siRowOrder1 + PIXELS_PER_WORD*siSelectWord + 1) & sauImageBuffer(IMAGE_WIDTH*siRowOrder1 + PIXELS_PER_WORD*siSelectWord + 2);
                    else
                        sauNextResultBuffer <= sauResultBuffer(4 to sauNextResultBuffer'length - 1) & sauImageBuffer(IMAGE_WIDTH*siRowOrder1 + PIXELS_PER_WORD*siSelectWord - 1) & sauImageBuffer(IMAGE_WIDTH*siRowOrder1 + PIXELS_PER_WORD*siSelectWord) & sauImageBuffer(IMAGE_WIDTH*siRowOrder1 + PIXELS_PER_WORD*siSelectWord + 1) & sauImageBuffer(IMAGE_WIDTH*siRowOrder1 + PIXELS_PER_WORD*siSelectWord + 2);
                    end if;
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

                sauImageBuffer <= cauImageBufferInit;
                sauResultBuffer <= cauResultBuffer;
            else
                sstState <= sstNextState;
                siWriteCount <= siNextWriteCount;
                siReadCount <= siNextReadCount;
                siAddress <= siNextAddress;
                
                slvSelectRowOrder <= slvNextSelectRowOrder;

                siSelectWord <= siNextSelectWord;

                sauResultBuffer <= sauNextResultBuffer;
            end if;
        end if;
    end process FSM_mem;

end rtl;
