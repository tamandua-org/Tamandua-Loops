-------------------------------------------------------------------
--
--  Fichero:
--    asyncRstSynchronizer.vhd  17/01/2024
--
--    (c) J.M. Mendias
--    Diseño Automático de Sistemas
--    Facultad de Informática. Universidad Complutense de Madrid
--
--  Propósito:
--    Sincroniza el reset para activación asíncrona desactivación
--    asíncrona
--
--  Notas de diseño:
--    Orientado a FPGA Xilinx 7 series: no reset y valor inicial
--
-------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity asyncRstSynchronizer is
  generic (
    STAGES : natural;         -- número de biestables del sincronizador
    XPOL   : std_logic        -- polaridad (en reposo) de la señal de reset
  );
  port (
    clk    : in  std_logic;   -- reloj del sistema
    rstIn  : in  std_logic;   -- rst de entrada
    rstOut : out std_logic    -- rst de salida
  );
end asyncRstSynchronizer;

-------------------------------------------------------------------

use work.common.all;

architecture syn of asyncRstSynchronizer is 

  signal rstAux : std_logic;
  
begin

  rstSynchronizer : synchronizer
    generic map ( STAGES => STAGES, XPOL => not XPOL )
    port map ( clk => clk, x => rstIn, xSync => rstAux );
    
  rstOut <= (rstAux or rstIn) when XPOL = '0' else (rstAux and rstIn);

end syn;
