-------------------------------------------------------------------
--
--  Fichero:
--    freqSynthesizer.vhd  16/01/2024
--
--    (c) J.M. Mendias
--    Diseño Automático de Sistemas
--    Facultad de Informática. Universidad Complutense de Madrid
--
--  Propósito:
--    Genera una señal de reloj de cierta frecuencia
--
--  Notas de diseño:
--    - Utiliza un PLL
--
-------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity freqSynthesizer is
  generic (
    FREQ_KHZ : natural;                 -- frecuencia del reloj de entrada en KHz
    MULTIPLY : natural range 1 to 64;   -- factor por el que multiplicar la frecuencia de entrada 
    DIVIDE   : natural range 1 to 128   -- divisor por el que dividir la frecuencia de entrada
  );
  port (
    clkIn  : in  std_logic;   -- reloj de entrada
    rdy    : out std_logic;   -- indica si el reloj de salida es válido
    clkOut : out std_logic    -- reloj de salida
  );
end freqSynthesizer;

-------------------------------------------------------------------

library unisim;
use unisim.vcomponents.all;

architecture syn of freqSynthesizer is 

  constant NORM_NSxKHZ : real    := 1_000_000.0;  -- Factor de normalización ns * KHz
  constant FVCOMIN_KHZ : natural := 800_000;      -- Frecuencia mínima de VCO
  
  signal clkLoop : std_logic;

begin

  clockManager : PLLE2_BASE
    generic map (
      BANDWIDTH          => "OPTIMIZED",
      CLKFBOUT_MULT      => MULTIPLY*FVCOMIN_KHZ/FREQ_KHZ,        
      CLKFBOUT_PHASE     => 0.0,
      CLKIN1_PERIOD      => NORM_NSxKHZ/real(FREQ_KHZ),   -- periodo de la entrada (en ns)
      CLKOUT0_DIVIDE     => DIVIDE*FVCOMIN_KHZ/FREQ_KHZ,
      CLKOUT1_DIVIDE     => 1,
      CLKOUT2_DIVIDE     => 1,
      CLKOUT3_DIVIDE     => 1,
      CLKOUT4_DIVIDE     => 1,
      CLKOUT5_DIVIDE     => 1,
      CLKOUT0_DUTY_CYCLE => 0.5,
      CLKOUT1_DUTY_CYCLE => 0.5,
      CLKOUT2_DUTY_CYCLE => 0.5,
      CLKOUT3_DUTY_CYCLE => 0.5,
      CLKOUT4_DUTY_CYCLE => 0.5,
      CLKOUT5_DUTY_CYCLE => 0.5,
      CLKOUT0_PHASE      => 0.0,
      CLKOUT1_PHASE      => 0.0,
      CLKOUT2_PHASE      => 0.0,
      CLKOUT3_PHASE      => 0.0,
      CLKOUT4_PHASE      => 0.0,
      CLKOUT5_PHASE      => 0.0,
      DIVCLK_DIVIDE      => 1,
      REF_JITTER1        => 0.0,
      STARTUP_WAIT       => "FALSE"
    )
    port map 
    (
      CLKOUT0  => clkOut,
      CLKOUT1  => open,
      CLKOUT2  => open,
      CLKOUT3  => open,
      CLKOUT4  => open,
      CLKOUT5  => open,
      CLKFBOUT => clkLoop,
      LOCKED   => rdy,
      CLKIN1   => clkIn,
      PWRDWN   => '0',
      RST      => '0',
      CLKFBIN  => clkLoop
    );
      
end syn;


