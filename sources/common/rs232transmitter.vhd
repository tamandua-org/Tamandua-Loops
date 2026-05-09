-------------------------------------------------------------------
--
--  Fichero:
--    rs232transmitter.vhd  15/7/2015
--
--    (c) J.M. Mendias
--    Dise�o Autom�tico de Sistemas
--    Facultad de Inform�tica. Universidad Complutense de Madrid
--
--  Prop�sito:
--    Conversor elemental de paralelo a una linea serie RS-232 con 
--    protocolo de strobe
--
--  Notas de dise�o:
--    - Parity: NONE
--    - Num data bits: 8
--    - Num stop bits: 1
--
-------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity rs232transmitter is
  generic (
    FREQ_KHZ : natural;  -- frecuencia de operacion en KHz
    BAUDRATE : natural   -- velocidad de comunicacion
  );
  port (
    -- host side
    clk     : in  std_logic;   -- reloj del sistema
    rst     : in  std_logic;   -- reset s�ncrono del sistema
    dataRdy : in  std_logic;   -- se activa durante 1 ciclo cada vez que hay un nuevo dato a transmitir
    data    : in  std_logic_vector (7 downto 0);   -- dato a transmitir
    busy    : out std_logic;   -- se activa mientras esta transmitiendo
    -- RS232 side
    TxD     : out std_logic    -- salida de datos serie del interfaz RS-232
  );
end rs232transmitter;

-------------------------------------------------------------------

use work.common.all;

architecture syn of rs232transmitter is

  signal baudCntCE, writeTxD : boolean;

begin

  baudCnt:
  process (clk)
    constant CYCLES : natural := (FREQ_KHZ*1000)/BAUDRATE;
    variable count  : natural range 0 to CYCLES-1 := 0;
  begin
    writeTxD <= (count = CYCLES-1);
    if rising_edge(clk) then
      if baudCntCE then
        if count = CYCLES - 1 then
          count := 0;
        else 
          count := count + 1;
        end if;
      else
        count := 0;
      end if;
    end if;
  end process;
  
  fsmd:
  process (clk)
    variable bitPos : natural range 0 to 10 := 0;   
    variable TxDShf : std_logic_vector(9 downto 0) := (others =>'1');
  begin
    TxD <= TxDShf(0);
    baudCntCE <= (bitPos /= 0);
    
    if rising_edge(clk) then
      if rst='1' then
        TxDShf := (others =>'1'); 
        bitPos := 0;
      else
      
        case bitPos is
          when 0 =>                            
            if dataRdy='1' then
              TxDShf := "1" & data & "0";
              bitPos := 1;
            end if;
          
          when 10 =>
            if writeTxD then
              TxDShf := '1' & TxDShf(9 downto 1);
              bitPos := 0;
            end if;
            
          when others =>                         
            if writeTxD then
              TxDShf := '1' & TxDShf(9 downto 1);
              bitPos := bitPos + 1;
            end if;
            
        end case;
      end if;
    end if;
  end process;
  
end syn;

