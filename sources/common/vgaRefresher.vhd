---------------------------------------------------------------------
--
--  Fichero:
--    vgaRefresher.vhd  22/01/2024
--
--    (c) J.M. Mendias
--    Diseño Automático de Sistemas
--    Facultad de Informática. Universidad Complutense de Madrid
--
--  Propósito:
--    Genera las señales de color y sincronismo de un interfaz VGA
--    con resolución 640x420 px
--
--  Notas de diseño:
--    - Válido para frecuencias de reloj multiplos de 25 MHz
--    
--
---------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity vgaRefresher is
  generic(
    FREQ_DIV  : natural;  -- razon entre la frecuencia de reloj del sistema y 25 MHz
    FREQ_KHZ  : natural
  );
  port ( 
    -- host side
    clk   : in  std_logic;   -- reloj del sistema
    line  : out std_logic_vector(9 downto 0);   -- numero de linea que se esta barriendo
    pixel : out std_logic_vector(9 downto 0);   -- numero de pixel que se esta barriendo
    R     : in  std_logic_vector(3 downto 0);   -- intensidad roja del pixel que se esta barriendo
    G     : in  std_logic_vector(3 downto 0);   -- intensidad verde del pixel que se esta barriendo
    B     : in  std_logic_vector(3 downto 0);   -- intensidad azul del pixel que se esta barriendo
    -- VGA side
    hSync : out std_logic := '0';   -- sincronizacion horizontal
    vSync : out std_logic := '0';   -- sincronizacion vertical
    RGB   : out std_logic_vector(11 downto 0) := (others => '0')   -- canales de color
  );
end vgaRefresher;

---------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;
use work.common.all;

architecture syn of vgaRefresher is

component freqSynthesizer
  generic (
    FREQ_KHZ : natural;                 -- frecuencia del reloj de entrada en KHz
    MULTIPLY : natural range 1 to 64;   -- factor por el que multiplicar la frecuencia de entrada 
    DIVIDE   : natural range 1 to 128   -- divisor por el que dividir la frecuencia de entrada
  );
  port (
    clkIn  : in  std_logic;   -- reloj de entrada
    rdy    : out std_logic;   -- indica si el reloj de salida es v�lido
    clkOut : out std_logic    -- reloj de salida
  );
end component;

  --constant CYCLESxPIXEL : natural := FREQ_DIV;
  constant PIXELSxLINE  : natural := 800;
  constant LINESxFRAME  : natural := 525;
     
  signal hSyncInt, vSyncInt : std_logic;

  --signal cycleCnt : natural range 0 to CYCLESxPIXEL-1 := 0;  
  signal pixelCnt : unsigned(pixel'range) := (others=>'0');
  signal lineCnt  : unsigned(line'range)  := (others=>'0');

  signal blanking : boolean;
  
  signal clk_25MHz : std_logic;
  signal pll_rdy   : std_logic;
  
begin

  clkGenerator: freqSynthesizer
    generic map (FREQ_KHZ => FREQ_KHZ, MULTIPLY => 1, DIVIDE => FREQ_DIV)
    port map ( clkIn => clk, rdy => pll_rdy, clkOut => clk_25MHz);

  counters:
  process (clk_25MHz)
  begin
    if rising_edge(clk_25MHz) then
    
      if pll_rdy = '0' then
        pixelCNt <= (others => '0');
        lineCnt <= (others => '0');

      elsif pixelCnt=PIXELSxLINE-1 then
        pixelCnt <= (others => '0');
        
        if lineCnt = LINESxFrame-1 then
          lineCnt <= (others => '0');
        else
          lineCnt <= lineCnt + 1;
        end if;
        
      else
      pixelCnt <= pixelCnt + 1;
      
      end if;
    end if;
  end process;

  pixel <= std_logic_vector(pixelCnt);
  line  <= std_logic_vector(lineCnt);
  
  hSyncInt <= '0' when (pixelCnt >= 656 and pixelCnt < 752) else '1';
  vSyncInt <= '0' when (lineCnt >= 490 and lineCnt < 492) else '1';        

  blanking <= (pixelCnt >= 640) or (lineCnt >= 480);
  
  outputRegisters:
  process (clk_25MHz)
  begin
    if rising_edge(clk_25MHz) then

      if pll_rdy = '0' then
         hSync <= '0';
         vSync <= '1';
         RGB <= (others => '0');
         
      else 
      hSync <= hSyncInt;
      vSync <= vSyncInt;
      
      if blanking then
        RGB <= (others => '0');
      else
        RGB <= R & G & B;
        
      end if;
    end if;
   end if;
  end process;
    
end syn;