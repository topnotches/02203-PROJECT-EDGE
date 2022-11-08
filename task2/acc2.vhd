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
    constant BUFFER_SIZE            : natural := IMAGE_WIDTH;
    constant BUFFER_WORDS           : natural := BUFFER_SIZE/4;
    constant TOTAL_PIXELS           : natural := IMAGE_WIDTH * IMAGE_HEIGHT;
    constant TOTAL_WORDS            : natural := TOTAL_PIXELS / PIXELS_PER_WORD;
    constant TOTAL_WORDS_WIDTH      : natural := IMAGE_WIDTH/4;
    constant TOTAL_MEM_ADDR         : natural := TOTAL_WORDS * 2;
    constant TOTAL_BUFFER_ROWS      : natural := 3;

    constant COUNTER_LEAD           : natural := IMAGE_WIDTH/PIXELS_PER_WORD;

    -- Image signals
    signal siWriteCount, siNextWriteCount : integer range 0 to TOTAL_WORDS := 0;
    signal siReadCount, siNextReadCount : integer range 0 to TOTAL_WORDS := 0;
    
    -- FSM signals
    type state_t is (stIdle, stRead, stWrite, stReset, stDone);
    signal sstState, sstNextState : state_t := stIdle;
    signal siAddress, siNextAddress : integer range 0 to TOTAL_MEM_ADDR - 1 := 0; 

    -- Buffer signals
    type imageBuffer_t is array (0 to BUFFER_WORDS - 1) of word_t;

    signal sauRowBuffer0, sauRowBuffer1, sauRowBuffer2 : imageBuffer_t;
    attribute ram_style : string;
    attribute ram_style of sauRowBuffer0 : signal is "distributed";
    attribute ram_style of sauRowBuffer1 : signal is "distributed";
    attribute ram_style of sauRowBuffer2 : signal is "distributed";

    signal slvBufferDataW : word_t := word_zero;
    signal slvBufferDataR0, slvBufferDataR1, slvBufferDataR2, slvBufferAsynchDataR0, slvBufferAsynchDataR1, slvBufferAsynchDataR2 : word_t := word_zero;
    signal slvTopSlack, slvMiddleSlack, slvBottomSlack, slvNextTopSlack, slvNextMiddleSlack, slvNextBottomSlack: halfword_t := halfword_zero;

    constant clvSelectRowOrderInit : std_logic_vector(2 downto 0) := "100";
    signal slvSelectRowOrder, slvNextSelectRowOrder : std_logic_vector(2 downto 0) := clvSelectRowOrderInit;

    signal siSelectWord, siNextSelectWord : integer range 0 to TOTAL_WORDS_WIDTH - 1 := 0;
    signal siBottomRowSelect, siMiddleRowSelect, siTopRowSelect : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal slvBottomRowRead, slvMiddleRowRead, slvTopRowRead : word_t := word_z;
    
    signal slvBuffersWE : std_logic_vector(2 downto 0) := (others => '0');
    
    signal siRowOrder0  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal siRowOrder1  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal siRowOrder2  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    
    type resultBuffer_t is array (0 to BUFFER_WIDTH_RESULT - 1) of byte_t;

    constant cauResultBuffer   : resultBuffer_t := (others => (others => '0'));
    signal sauResultBuffer, sauNextResultBuffer   : resultBuffer_t := cauResultBuffer;

    signal slvArithmeticResult : word_t := word_zero;
    -- Port signals
    
begin



    -- Combinatorial circuit
    process (siAddress, slvSelectRowOrder, siRowOrder0, siRowOrder1, siRowOrder2)
    begin
        addr <= std_logic_vector(to_unsigned(siAddress, addr'length));
        
        siRowOrder0         <= to_integer(unsigned'(slvSelectRowOrder(2) & slvSelectRowOrder(0)));
        siRowOrder1         <= to_integer(unsigned'(slvSelectRowOrder(0) & slvSelectRowOrder(1)));
        siRowOrder2         <= to_integer(unsigned'(slvSelectRowOrder(1) & slvSelectRowOrder(2)));
        siTopRowSelect      <= 2 - siRowOrder2;
        siMiddleRowSelect   <= 2 - siRowOrder1;
        siBottomRowSelect   <= 2 - siRowOrder0;

    end process;

    with siTopRowSelect select slvTopRowRead <=
        slvBufferDataR0 when 0,
        slvBufferDataR1 when 1,
        slvBufferDataR2 when 2;
    with siMiddleRowSelect select slvMiddleRowRead <=
        slvBufferDataR0 when 0,
        slvBufferDataR1 when 1,
        slvBufferDataR2 when 2;
    with siBottomRowSelect select slvBottomRowRead <=
        slvBufferDataR0 when 0,
        slvBufferDataR1 when 1,
        slvBufferDataR2 when 2;

        
    slvBufferDataW <= dataR(dataR'length - (1 + BITS_PER_PIXEL*3) downto dataR'length - (BITS_PER_PIXEL*4))
                    & dataR(dataR'length - (1 + BITS_PER_PIXEL*2) downto dataR'length - (BITS_PER_PIXEL*3))
                    & dataR(dataR'length - (1 + BITS_PER_PIXEL) downto dataR'length - (BITS_PER_PIXEL*2))
                    & dataR(dataR'length - (1) downto dataR'length - (BITS_PER_PIXEL));

    dataW <= std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(3))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(2))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(1))) & std_logic_vector(unsigned(byte_one)-unsigned(sauResultBuffer(0)));
    
    --BIG CONCURRENT STATEMENT

    FSM_logic : process(sstState, siWriteCount, siReadCount, siAddress, sauRowBuffer0, sauRowBuffer1, sauRowBuffer2, siTopRowSelect, siMiddleRowSelect, siBottomRowSelect, slvTopSlack, slvMiddleSlack, slvBottomSlack, slvBufferDataR0, slvBufferDataR1, slvBufferDataR2, sauResultBuffer, start, dataR, slvSelectRowOrder, siBottomRowSelect, siRowOrder0, siRowOrder1, siSelectWord)
        
        -- Next State Procedure 
        procedure pSetNextValues(nextState : in state_t;
                                incrementCounter : in std_logic;
                                nextAddress : in integer range 0 to (TOTAL_WORDS * 2);
                                enable : in std_logic;
                                writeEnable : in std_logic) is
        begin
            sstNextState <= nextState;
            siNextAddress <= nextAddress;
            
            sauNextResultBuffer <= sauResultBuffer;

            siNextWriteCount <= siWriteCount;
            siNextReadCount <= siReadCount;

            siNextSelectWord <= siSelectWord;
            slvNextSelectRowOrder <= slvSelectRowOrder;

            slvNextTopSlack <= slvTopSlack;
            slvNextMiddleSlack <= slvMiddleSlack;
            slvNextBottomSlack <= slvBottomSlack;

            en <= enable;
            slvBuffersWE <= (others => '0'); 
            if incrementCounter = '1' then


                if siWriteCount < TOTAL_WORDS and siReadCount > COUNTER_LEAD + 3 then
                    siNextWriteCount <= siWriteCount + 1;
                    we <= writeEnable;
                end if;

                slvBuffersWE(siBottomRowSelect) <= '1';

                if siReadCount < TOTAL_WORDS then
                    siNextReadCount <= siReadCount + 1;
                end if;

                if siSelectWord < TOTAL_WORDS_WIDTH - 1 then
                    siNextSelectWord <= siSelectWord + 1;  
                else
                    siNextSelectWord <= 0;

                    if siSelectWord = TOTAL_WORDS_WIDTH - 1 then
                        slvNextSelectRowOrder <= slvSelectRowOrder(1 downto 0) & slvSelectRowOrder(2);
                    end if;
                end if;

                if siWriteCount = TOTAL_WORDS - 1 then
                    sstNextState <= stDone;
                end if;
            else

                slvNextTopSlack <= slvTopRowRead(slvTopSlack'length - 1 downto 0);
                slvNextMiddleSlack <= slvMiddleRowRead(slvMiddleSlack'length - 1 downto 0);
                slvNextBottomSlack <= slvBufferDataW(slvBufferDataW'length/2 - 1 downto 0);
                slvArithmeticResult<=slvMiddleSlack(byte_t'length - 1 downto 0) & slvMiddleRowRead(slvMiddleRowRead'length - 1 downto byte_t'length);

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

                if siReadCount >= COUNTER_LEAD then
                    sauNextResultBuffer <= sauResultBuffer(4 to sauNextResultBuffer'length - 1)
                    & slvArithmeticResult(slvArithmeticResult'length - (1) downto slvArithmeticResult'length - (BITS_PER_PIXEL))
                    & slvArithmeticResult(slvArithmeticResult'length - (1 + BITS_PER_PIXEL) downto slvArithmeticResult'length - (BITS_PER_PIXEL*2))
                    & slvArithmeticResult(slvArithmeticResult'length - (1 + BITS_PER_PIXEL*2) downto slvArithmeticResult'length - (BITS_PER_PIXEL*3))
                    & slvArithmeticResult(slvArithmeticResult'length - (1 + BITS_PER_PIXEL*3) downto slvArithmeticResult'length - (BITS_PER_PIXEL*4));
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

                sauResultBuffer <= cauResultBuffer;
            else
                sstState <= sstNextState;
                siWriteCount <= siNextWriteCount;
                siReadCount <= siNextReadCount;
                siAddress <= siNextAddress;
                
                slvSelectRowOrder <= slvNextSelectRowOrder;

                siSelectWord <= siNextSelectWord;

                sauResultBuffer <= sauNextResultBuffer;
                
                slvTopSlack <= slvNextTopSlack;
                slvMiddleSlack <= slvNextMiddleSlack;
                slvBottomSlack <= slvNextBottomSlack;
            end if;
            
            slvBufferDataR0 <= slvBufferAsynchDataR0;
            slvBufferDataR1 <= slvBufferAsynchDataR1;
            slvBufferDataR2 <= slvBufferAsynchDataR2;
        end if;
    end process FSM_mem;
    RAM : process(clk, reset, siSelectWord, sauRowBuffer0, sauRowBuffer1, sauRowBuffer2)
    begin
        if rising_edge(clk) then
            if (slvBuffersWE(0) = '1') then
                sauRowBuffer0((siSelectWord)) <= slvBufferDataW;
            end if;

            if (slvBuffersWE(1) = '1') then
                sauRowBuffer1((siSelectWord)) <= slvBufferDataW;
            end if;
    

            if (slvBuffersWE(2) = '1') then
                sauRowBuffer2((siSelectWord)) <= slvBufferDataW;
            end if;
        end if;

        slvBufferAsynchDataR0 <= sauRowBuffer0(siSelectWord);
        slvBufferAsynchDataR1 <= sauRowBuffer1(siSelectWord);
        slvBufferAsynchDataR2 <= sauRowBuffer2(siSelectWord);    
    end process RAM;

end rtl;
