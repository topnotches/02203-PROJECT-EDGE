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
        truncation : natural range 0 to 7 := 0
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

    signal salvRowBuffer0, salvRowBuffer1, salvRowBuffer2 : imageBuffer_t;
    attribute ram_style : string;
    attribute ram_style of salvRowBuffer0 : signal is "distributed";
    attribute ram_style of salvRowBuffer1 : signal is "distributed";
    attribute ram_style of salvRowBuffer2 : signal is "distributed";

    signal slvBufferDataW : word_t := word_zero;
    signal slvBufferDataR0, slvBufferDataR1, slvBufferDataR2, slvBufferAsynchDataR0, slvBufferAsynchDataR1, slvBufferAsynchDataR2 : word_t := word_zero;
    signal slvTopSlack, slvMiddleSlack, slvBottomSlack, slvNextTopSlack, slvNextMiddleSlack, slvNextBottomSlack: halfword_t := halfword_zero;

    constant clvSelectRowOrderInit : std_logic_vector(2 downto 0) := "100";
    signal slvSelectRowOrder, slvNextSelectRowOrder : std_logic_vector(2 downto 0) := clvSelectRowOrderInit;

    signal siSelectWord, siNextSelectWord : integer range 0 to TOTAL_WORDS_WIDTH - 1 := 0;

    signal siLineCount, siNextLineCount : integer range 0 to IMAGE_HEIGHT + 1 := 0;

    signal siBottomRowSelect, siMiddleRowSelect, siTopRowSelect : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal slvBottomRowRead, slvNextBottomRowRead, slvMiddleRowRead, slvTopRowRead : word_t := word_z;
    
    signal slvBuffersWE : std_logic_vector(2 downto 0) := (others => '0');
    
    signal siRowOrder0  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal siRowOrder1  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    signal siRowOrder2  : integer range 0 to TOTAL_BUFFER_ROWS - 1 := 0;
    
    type resultBuffer_t is array (0 to BUFFER_WIDTH_RESULT - 1) of byte_t;

    constant calvResultBuffer   : resultBuffer_t := (others => (others => '0'));
    signal salvResultBuffer, salvNextResultBuffer : resultBuffer_t := calvResultBuffer;

    signal slvArithmeticResult : word_t := word_zero;

    type filterResults_t is array (0 to 3) of signed(3 + byte_t'length - truncation downto truncation);
    signal sasGxPartialSums, sasGyPartialSums : filterResults_t := (others => (others => '0'));
    
    type xyResults_t is array (0 to 3) of unsigned(7 downto truncation);
    signal sauGxResults, sauGyResults, sauFilterResults : xyResults_t := (others => (others => '0')); 

    type xyRowPixels_t is array (0 to 5) of std_logic_vector(7 downto truncation);
    signal salvDotPixelsTop    : xyRowPixels_t := (others => (others => '0')); 
    signal salvDotPixelsMiddle : xyRowPixels_t := (others => (others => '0')); 
    signal salvDotPixelsBottom : xyRowPixels_t := (others => (others => '0')); 
    signal slSetupRun, slNextSetupRun : std_logic := '1';



    -- Port signals
begin



    -- Combinatorial circuit
    process (siAddress, slvSelectRowOrder, siRowOrder0, siRowOrder1, siRowOrder2, salvDotPixelsTop, salvDotPixelsMiddle, salvDotPixelsBottom,
    slvTopRowRead, slvMiddleRowRead, slvBottomRowRead, slvTopSlack, slvMiddleSlack, slvBottomSlack, siLineCount, sasGxPartialSums, sasGyPartialSums, sauGxResults,
    sauGyResults, siLineCount, siSelectWord)
    begin
        addr <= std_logic_vector(to_unsigned(siAddress, addr'length));
        
        siRowOrder0         <= to_integer(unsigned'(slvSelectRowOrder(2) & slvSelectRowOrder(0)));
        siRowOrder1         <= to_integer(unsigned'(slvSelectRowOrder(0) & slvSelectRowOrder(1)));
        siRowOrder2         <= to_integer(unsigned'(slvSelectRowOrder(1) & slvSelectRowOrder(2)));
        siTopRowSelect      <= 2 - siRowOrder2;
        siMiddleRowSelect   <= 2 - siRowOrder1;
        siBottomRowSelect   <= 2 - siRowOrder0;

        salvDotPixelsTop(0) <= slvTopSlack(slvTopSlack'length - 1 downto slvTopSlack'length - byte_t'length + truncation);
        salvDotPixelsTop(1) <= slvTopSlack(slvTopSlack'length - byte_t'length - 1 + truncation downto truncation);
        salvDotPixelsTop(2) <= slvTopRowRead(slvTopRowRead'length - 1 downto slvTopRowRead'length - byte_t'length + truncation);
        salvDotPixelsTop(3) <= slvTopRowRead(slvTopRowRead'length - byte_t'length - 1 downto slvTopRowRead'length - byte_t'length*2 + truncation);
        salvDotPixelsTop(4) <= slvTopRowRead(slvTopRowRead'length - byte_t'length*2 + truncation - 1 downto slvTopRowRead'length - byte_t'length*3 + truncation);
        salvDotPixelsTop(5) <= slvTopRowRead(slvTopRowRead'length - byte_t'length*3 + truncation - 1 downto slvTopRowRead'length - byte_t'length*4 + truncation);


        salvDotPixelsMiddle(0) <= slvMiddleSlack(slvMiddleSlack'length - 1 downto slvMiddleSlack'length - byte_t'length + truncation);
        salvDotPixelsMiddle(1) <= slvMiddleSlack(slvMiddleSlack'length - byte_t'length - 1 + truncation downto truncation);
        salvDotPixelsMiddle(2) <= slvMiddleRowRead(slvMiddleRowRead'length - 1 downto slvMiddleRowRead'length - byte_t'length + truncation);
        salvDotPixelsMiddle(3) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length - 1 downto slvMiddleRowRead'length - byte_t'length*2 + truncation);
        salvDotPixelsMiddle(4) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length*2 + truncation - 1 downto slvMiddleRowRead'length - byte_t'length*3 + truncation);
        salvDotPixelsMiddle(5) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length*3 + truncation - 1 downto slvMiddleRowRead'length - byte_t'length*4 + truncation);


        salvDotPixelsBottom(0) <= slvBottomSlack(slvBottomSlack'length - 1 downto slvBottomSlack'length - byte_t'length + truncation);
        salvDotPixelsBottom(1) <= slvBottomSlack(slvBottomSlack'length - byte_t'length - 1 + truncation downto truncation);
        salvDotPixelsBottom(2) <= slvBottomRowRead(slvBottomRowRead'length - 1 downto slvBottomRowRead'length - byte_t'length + truncation);
        salvDotPixelsBottom(3) <= slvBottomRowRead(slvBottomRowRead'length - byte_t'length - 1 downto slvBottomRowRead'length - byte_t'length*2 + truncation);
        salvDotPixelsBottom(4) <= slvBottomRowRead(slvBottomRowRead'length - byte_t'length*2 + truncation - 1 downto slvBottomRowRead'length - byte_t'length*3 + truncation);
        salvDotPixelsBottom(5) <= slvBottomRowRead(slvBottomRowRead'length - byte_t'length*3 + truncation - 1 downto slvBottomRowRead'length - byte_t'length*4 + truncation);

        sasGxPartialSums(0) <= abs(
        - signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))
        - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(0) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsMiddle(2) & "0"))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(2)))
        );
        sasGxPartialSums(1) <= abs(
        - signed(std_logic_vector'("0000" & salvDotPixelsTop(1)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(3)))
        - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(1) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsMiddle(3) & "0"))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(1)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(3)))
        );
        sasGxPartialSums(2) <= abs(
        - signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(4)))
        - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(2) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsMiddle(4) & "0"))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(2)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(4)))
        );
        sasGxPartialSums(3) <= abs(
        - signed(std_logic_vector'("0000" & salvDotPixelsTop(3)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(5)))
        - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(3) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsMiddle(5) & "0"))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(3)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(5)))
        );
        
        
        sasGyPartialSums(0) <= abs(
          signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(1) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(2)))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(1) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(2)))
        );
        sasGyPartialSums(1) <= abs(
          signed(std_logic_vector'("0000" & salvDotPixelsTop(1)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(2) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(3)))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(1))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(2) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(3)))
        );
        sasGyPartialSums(2) <= abs(
          signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(3) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(4)))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(2))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(3) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(4)))
        );
        sasGyPartialSums(3) <= abs(
          signed(std_logic_vector'("0000" & salvDotPixelsTop(3)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(4) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(5)))
        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(3))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(4) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(5)))
        );
    
    
        sauGyResults(0) <= unsigned((sasGyPartialSums(0)(sasGyPartialSums(0)'length - 2 downto sasGyPartialSums(0)'length - 1 - byte_t'length)));
        sauGyResults(1) <= unsigned((sasGyPartialSums(1)(sasGyPartialSums(1)'length - 2 downto sasGyPartialSums(1)'length - 1 - byte_t'length)));
        sauGyResults(2) <= unsigned((sasGyPartialSums(2)(sasGyPartialSums(2)'length - 2 downto sasGyPartialSums(2)'length - 1 - byte_t'length)));
        sauGyResults(3) <= unsigned((sasGyPartialSums(3)(sasGyPartialSums(3)'length - 2 downto sasGyPartialSums(3)'length - 1 - byte_t'length)));
    
        sauGxResults(0) <= unsigned((sasGxPartialSums(0)(sasGxPartialSums(0)'length - 2 downto sasGxPartialSums(0)'length - 1 - byte_t'length)));
        sauGxResults(1) <= unsigned((sasGxPartialSums(1)(sasGxPartialSums(1)'length - 2 downto sasGxPartialSums(1)'length - 1 - byte_t'length)));
        sauGxResults(2) <= unsigned((sasGxPartialSums(2)(sasGxPartialSums(2)'length - 2 downto sasGxPartialSums(2)'length - 1 - byte_t'length)));
        sauGxResults(3) <= unsigned((sasGxPartialSums(3)(sasGxPartialSums(3)'length - 2 downto sasGxPartialSums(3)'length - 1 - byte_t'length)));
        
        sauFilterResults(0) <= sauGxResults(0) + sauGyResults(0);
        sauFilterResults(1) <= sauGxResults(1) + sauGyResults(1);
        sauFilterResults(2) <= sauGxResults(2) + sauGyResults(2);
        sauFilterResults(3) <= sauGxResults(3) + sauGyResults(3);


        if siLineCount = 1 then
            
            salvDotPixelsTop(0) <= slvMiddleSlack(slvMiddleSlack'length - 1 downto slvMiddleSlack'length - byte_t'length + truncation);
            salvDotPixelsTop(1) <= slvMiddleSlack(slvMiddleSlack'length - byte_t'length - 1 + truncation downto truncation);
            salvDotPixelsTop(2) <= slvMiddleRowRead(slvMiddleRowRead'length - 1 downto slvMiddleRowRead'length - byte_t'length + truncation);
            salvDotPixelsTop(3) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length - 1 downto slvMiddleRowRead'length - byte_t'length*2 + truncation);
            salvDotPixelsTop(4) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length*2 + truncation - 1 downto slvMiddleRowRead'length - byte_t'length*3 + truncation);
            salvDotPixelsTop(5) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length*3 + truncation - 1 downto slvMiddleRowRead'length - byte_t'length*4 + truncation);

        end if;

        if siLineCount = IMAGE_HEIGHT then
            
            salvDotPixelsBottom(0) <= slvMiddleSlack(slvMiddleSlack'length - 1 downto slvMiddleSlack'length - byte_t'length + truncation);
            salvDotPixelsBottom(1) <= slvMiddleSlack(slvMiddleSlack'length - byte_t'length - 1 + truncation downto truncation);
            salvDotPixelsBottom(2) <= slvMiddleRowRead(slvMiddleRowRead'length - 1 downto slvMiddleRowRead'length - byte_t'length + truncation);
            salvDotPixelsBottom(3) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length - 1 downto slvMiddleRowRead'length - byte_t'length*2 + truncation);
            salvDotPixelsBottom(4) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length*2 + truncation - 1 downto slvMiddleRowRead'length - byte_t'length*3 + truncation);
            salvDotPixelsBottom(5) <= slvMiddleRowRead(slvMiddleRowRead'length - byte_t'length*3 + truncation - 1 downto slvMiddleRowRead'length - byte_t'length*4 + truncation);

        end if;

        if siLineCount = 1 and siSelectWord = 1 then
            
            salvDotPixelsTop(1) <= slvMiddleRowRead(slvMiddleRowRead'length - 1 downto slvMiddleRowRead'length - byte_t'length + truncation);
            salvDotPixelsMiddle(1) <= slvMiddleRowRead(slvMiddleRowRead'length - 1 downto slvMiddleRowRead'length - byte_t'length + truncation);
        elsif siSelectWord = 1 then
        
            sasGxPartialSums(0) <= abs(
                - signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(1)))
                - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(0) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsMiddle(1) & "0"))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(1)))
            );
            sasGxPartialSums(1) <= abs(
                - signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(3)))
                - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(2) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsMiddle(3) & "0"))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(2)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(3)))
            );
            sasGyPartialSums(0) <= abs(
                  signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(1) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(1)))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(1) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(1)))
              );
            sasGyPartialSums(1) <= abs(
                  signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(2) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(3)))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(2))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(2) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(3)))
            );
            
            if siLineCount = 2 then
                
                sasGxPartialSums(0) <= abs(
                    - signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(1)))
                    - signed(std_logic_vector'("000"  & salvDotPixelsTop(0) & "0" ))     +  signed(std_logic_vector'("000"  & salvDotPixelsTop(1) & "0"))
                    - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(1)))
                );
                
                sasGyPartialSums(0) <= abs(
                    signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(1) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(1)))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(1) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(1)))
                );
            end if;
            
        end if;
        if siSelectWord = 0 then
        
            if siLineCount = 2 or siLineCount = 3 then
                sasGxPartialSums(0) <= abs(
                    - signed(std_logic_vector'("0000" & salvDotPixelsMiddle(0)))         +  signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))
                    - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(0) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsTop(2) & "0"))
                    - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(2)))
                );
                sasGxPartialSums(1) <= abs(
                    - signed(std_logic_vector'("0000" & salvDotPixelsMiddle(1)))         +  signed(std_logic_vector'("0000" & salvDotPixelsTop(3)))
                    - signed(std_logic_vector'("000"  & salvDotPixelsMiddle(1) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsTop(3) & "0"))
                    - signed(std_logic_vector'("0000" & salvDotPixelsBottom(1)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(3)))
                );
                sasGxPartialSums(2) <= abs(
                    - signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(4)))
                    - signed(std_logic_vector'("000"  & salvDotPixelsTop(2) & "0" ))     +  signed(std_logic_vector'("000"  & salvDotPixelsTop(4) & "0"))
                    - signed(std_logic_vector'("0000" & salvDotPixelsBottom(2)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(4)))
                );
                sasGxPartialSums(3) <= abs(
                    - signed(std_logic_vector'("0000" & salvDotPixelsTop(3)))            +  signed(std_logic_vector'("0000" & salvDotPixelsTop(5)))
                    - signed(std_logic_vector'("000"  & salvDotPixelsTop(3) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsTop(5) & "0"))
                    - signed(std_logic_vector'("0000" & salvDotPixelsBottom(3)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(5)))
                );
                sasGyPartialSums(0) <= abs(
                  signed(std_logic_vector'("0000" & salvDotPixelsMiddle(0)))    + signed(std_logic_vector'("000"  & salvDotPixelsMiddle(1) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(2)))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0)))    - signed(std_logic_vector'("000"  & salvDotPixelsBottom(1) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(2)))
                );
                sasGyPartialSums(1) <= abs(
                  signed(std_logic_vector'("0000" & salvDotPixelsMiddle(1)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(2) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(3)))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(1))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(2) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(3)))
                );
                sasGyPartialSums(2) <= abs(
                  signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(3) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(4)))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(2))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(3) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(4)))
                );
                sasGyPartialSums(3) <= abs(
                  signed(std_logic_vector'("0000" & salvDotPixelsTop(3)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(4) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(5)))
                - signed(std_logic_vector'("0000" & salvDotPixelsBottom(3))) - signed(std_logic_vector'("000"  & salvDotPixelsBottom(4) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(5)))
                );
                if siLineCount = 3 then

                    sasGxPartialSums(0) <= abs(
                        - signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))         +  signed(std_logic_vector'("0000" & salvDotPixelsTop(2)))
                        - signed(std_logic_vector'("000"  & salvDotPixelsTop(0) & "0" ))  +  signed(std_logic_vector'("000"  & salvDotPixelsMiddle(2) & "0"))
                        - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0)))         +  signed(std_logic_vector'("0000" & salvDotPixelsBottom(2)))
                    );

                    sasGyPartialSums(0) <= abs(
                        signed(std_logic_vector'("0000" & salvDotPixelsTop(0)))    + signed(std_logic_vector'("000"  & salvDotPixelsTop(1) & "0" ))    + signed(std_logic_vector'("0000"  & salvDotPixelsTop(2)))
                    - signed(std_logic_vector'("0000" & salvDotPixelsBottom(0)))    - signed(std_logic_vector'("000"  & salvDotPixelsBottom(1) & "0" )) - signed(std_logic_vector'("0000"  & salvDotPixelsBottom(2)))
                    );
                end if;
            end if ;

        end if;
    end process;

    with siTopRowSelect select slvTopRowRead <=
        slvBufferDataR0 when 0,
        slvBufferDataR1 when 1,
        slvBufferDataR2 when 2;
    with siMiddleRowSelect select slvMiddleRowRead <=
        slvBufferDataR0 when 0,
        slvBufferDataR1 when 1,
        slvBufferDataR2 when 2;

        
    slvBufferDataW <= dataR(dataR'length - (1 + BITS_PER_PIXEL*3) downto dataR'length - (BITS_PER_PIXEL*4))
                    & dataR(dataR'length - (1 + BITS_PER_PIXEL*2) downto dataR'length - (BITS_PER_PIXEL*3))
                    & dataR(dataR'length - (1 + BITS_PER_PIXEL) downto dataR'length - (BITS_PER_PIXEL*2))
                    & dataR(dataR'length - (1) downto dataR'length - (BITS_PER_PIXEL));

    dataW <= salvResultBuffer(3) & salvResultBuffer(2) & salvResultBuffer(1) & salvResultBuffer(0);
    
    --BIG CONCURRENT STATEMENT 



    slvArithmeticResult <= std_logic_vector(sauFilterResults(0)) & std_logic_vector(sauFilterResults(1)) & std_logic_vector(sauFilterResults(2)) & std_logic_vector(sauFilterResults(3));
                

    FSM_logic : process(sstState, siWriteCount, siReadCount, siAddress, salvRowBuffer0, salvRowBuffer1, salvRowBuffer2,
                siTopRowSelect, siMiddleRowSelect,siBottomRowSelect, slvTopSlack, slvMiddleSlack, slvBottomSlack,
                slvBufferDataR0, slvBufferDataR1, slvBufferDataR2, salvResultBuffer, start, dataR, slvSelectRowOrder,
                siBottomRowSelect, siRowOrder0, siRowOrder1, siSelectWord, slvBufferDataW, slSetupRun, slvArithmeticResult,
                slvTopRowRead, slvMiddleRowRead, slvBottomRowRead, siLineCount)
        
        -- Next State Procedure 
        procedure pSetNextValues(nextState : in state_t;
                                incrementCounter : in std_logic;
                                nextAddress : in integer range 0 to (TOTAL_WORDS * 2);
                                enable : in std_logic;
                                writeEnable : in std_logic) is
        begin
            sstNextState <= nextState;
            siNextAddress <= nextAddress;
            
            salvNextResultBuffer <= salvResultBuffer;

            siNextWriteCount <= siWriteCount;
            siNextReadCount <= siReadCount;
            siNextLineCount <= siLineCount;

            siNextSelectWord <= siSelectWord;
            slvNextSelectRowOrder <= slvSelectRowOrder;

            slvNextTopSlack <= slvTopSlack;
            slvNextMiddleSlack <= slvMiddleSlack;
            slvNextBottomSlack <= slvBottomSlack;

            slvNextBottomRowRead <= slvBottomRowRead;

            en <= enable;
            slvBuffersWE <= (others => '0'); 
            slNextSetupRun <= slSetupRun;

            if incrementCounter = '1' then
                if siWriteCount < TOTAL_WORDS and siReadCount > COUNTER_LEAD + 2 then
                    siNextWriteCount <= siWriteCount + 1;
                    we <= writeEnable;
                end if;

                slvBuffersWE(siBottomRowSelect) <= '1';

                if siReadCount < TOTAL_WORDS then
                    siNextReadCount <= siReadCount + 1;
                end if;

                if siSelectWord < TOTAL_WORDS_WIDTH - 1 and slSetupRun = '0' then
                    siNextSelectWord <= siSelectWord + 1;  
                else
                    siNextSelectWord <= 0;

        
                    if siSelectWord = TOTAL_WORDS_WIDTH - 1 then
                        slvNextSelectRowOrder <= slvSelectRowOrder(1 downto 0) & slvSelectRowOrder(2);
                        siNextLineCount <= siLineCount + 1;
                    end if;
                end if;

                if siWriteCount = TOTAL_WORDS - 1 then
                    sstNextState <= stDone;
                end if;

            else

                slvNextTopSlack <= slvTopRowRead(slvTopSlack'length - 1 downto 0);
                slvNextMiddleSlack <= slvMiddleRowRead(slvMiddleSlack'length - 1 downto 0);
                slvNextBottomSlack <= slvBottomRowRead(slvBottomSlack'length - 1 downto 0);
                
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

                if siReadCount >= COUNTER_LEAD then
                    salvNextResultBuffer <= salvResultBuffer(4 to salvNextResultBuffer'length - 1)
                    & slvArithmeticResult(slvArithmeticResult'length - (1) downto slvArithmeticResult'length - (BITS_PER_PIXEL))
                    & slvArithmeticResult(slvArithmeticResult'length - (1 + BITS_PER_PIXEL) downto slvArithmeticResult'length - (BITS_PER_PIXEL*2))
                    & slvArithmeticResult(slvArithmeticResult'length - (1 + BITS_PER_PIXEL*2) downto slvArithmeticResult'length - (BITS_PER_PIXEL*3))
                    & slvArithmeticResult(slvArithmeticResult'length - (1 + BITS_PER_PIXEL*3) downto slvArithmeticResult'length - (BITS_PER_PIXEL*4));
                end if;
                
            when stWrite =>
                pSetNextValues(stRead, '1', siReadCount, '1', '1');

                slNextSetupRun <= '0';
                slvNextBottomRowRead <= slvBufferDataW;
            when stDone =>
                pSetNextValues(stDone, '0', 0, '0', '0');
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

                salvResultBuffer <= calvResultBuffer;
            else
                slSetupRun <= slNextSetupRun;
                sstState <= sstNextState;
                siWriteCount <= siNextWriteCount;
                siReadCount <= siNextReadCount;
                siAddress <= siNextAddress;
                
                slvSelectRowOrder <= slvNextSelectRowOrder;

                siSelectWord <= siNextSelectWord;

                salvResultBuffer <= salvNextResultBuffer;
                
                slvTopSlack <= slvNextTopSlack;
                slvMiddleSlack <= slvNextMiddleSlack;
                slvBottomSlack <= slvNextBottomSlack;

                slvBottomRowRead <= slvNextBottomRowRead;

                siLineCount <= siNextLineCount;
            end if;
            
            slvBufferDataR0 <= slvBufferAsynchDataR0;
            slvBufferDataR1 <= slvBufferAsynchDataR1;
            slvBufferDataR2 <= slvBufferAsynchDataR2;
        end if;
    end process FSM_mem;
    RAM : process(clk, reset, siSelectWord, salvRowBuffer0, salvRowBuffer1, salvRowBuffer2)
    begin
        if rising_edge(clk) then
            if (slvBuffersWE(0) = '1') then
                salvRowBuffer0((siSelectWord)) <= slvBufferDataW;
            end if;

            if (slvBuffersWE(1) = '1') then
                salvRowBuffer1((siSelectWord)) <= slvBufferDataW;
            end if;
    

            if (slvBuffersWE(2) = '1') then
                salvRowBuffer2((siSelectWord)) <= slvBufferDataW;
            end if;
        end if;

        slvBufferAsynchDataR0 <= salvRowBuffer0(siSelectWord);
        slvBufferAsynchDataR1 <= salvRowBuffer1(siSelectWord);
        slvBufferAsynchDataR2 <= salvRowBuffer2(siSelectWord);    
    end process RAM;

end rtl;
