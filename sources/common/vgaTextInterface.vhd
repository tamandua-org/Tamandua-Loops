---------------------------------------------------------------------
--
--  Fichero:
--    vgaTextInterface.vhd  12/09/2023
--
--    (c) J.M. Mendias
--    Dise�o Autom�tico de Sistemas
--    Facultad de Inform�tica. Universidad Complutense de Madrid
--
--  Prop�sito:
--    Genera las se�ales de color y sincronismo de un interfaz texto
--    VGA con resoluci�n de 80x30 caracteres de 8x16 pixeles.
--
--  Notas de dise�o:
--    - Para frecuencias a partir de 50 Mhz en multiplos de 25 MHz
--    - Incluye una memoria de refresco para almacenar los caracteres
--      a visualizar y una memoria de mapas de bits de cada caracter 
--
---------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity vgaTextInterface is
  generic(
    FREQ_DIV : natural;  -- valor por el que dividir la frecuencia del reloj del sistema para obtener 25 MHz
    BGCOLOR  : std_logic_vector (11 downto 0); -- color del background
    FGCOLOR  : std_logic_vector (11 downto 0)  -- color del foreground
  );
  port ( 
    -- host side
    clk     : in std_logic;   -- reloj del sistema
    clear   : in std_logic;   -- borra la memoria de refresco
    dataRdy : in std_logic;   -- se activa durante 1 ciclo cada vez que hay un nuevo caracter a visualizar
    char    : in std_logic_vector (7 downto 0);   -- codigo ASCII del caracter a visualizar
    x       : in std_logic_vector (6 downto 0);   -- columna en donde visualizar el caracter
    y       : in std_logic_vector (4 downto 0);   -- fila en donde visualizar el caracter
    --
    col     : out std_logic_vector (6 downto 0);   -- numero de columna que se esta barriendo
    uCol    : out std_logic_vector (2 downto 0);   -- numero de microcolumna que se esta barriendo
    row     : out std_logic_vector (4 downto 0);   -- numero de fila que se esta barriendo
    uRow    : out std_logic_vector (3 downto 0);   -- numero de microfila que se esta barriendo
    -- VGA side
    hSync  : out std_logic;   -- sincronizacion horizontal
    vSync  : out std_logic;   -- sincronizacion vertical
    RGB    : out std_logic_vector (11 downto 0)   -- canales de color
  );
end vgaTextInterface;

---------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;
use work.common.all;

architecture syn of vgaTextInterface is

component vgaRefresher
  generic(
    FREQ_DIV  : natural  -- razon entre la frecuencia de reloj del sistema y 25 MHz
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
end component;

  constant COLSxLINE  : natural := 80;
  constant ROWSxFRAME : natural := 30;

  signal pixel : std_logic_vector (9 downto 0);
  signal line  : std_logic_vector (9 downto 0);

  signal colInt   : std_logic_vector (x'range);
  signal rowInt   : std_logic_vector (y'range);
  signal uColInt  : std_logic_vector (2 downto 0);
  signal uRowInt  : std_logic_vector (3 downto 0);
  
  signal clearX   : unsigned (x'range) := (others => '0');
  signal clearY   : unsigned (y'range) := (others => '0');
  signal clearing : std_logic;
 
  signal color : std_logic_vector (11 downto 0);
 
  signal ramRdAddr, ramWrAddr : std_logic_vector (11 downto 0);
  signal we : std_logic;
  signal asciiCode, ramWrData : std_logic_vector (7 downto 0);
  
  type   ramType is array (0 to 2**(x'length+y'length)-1) of std_logic_vector (char'range);
  signal ram : ramType;
  
  signal romAddr     : std_logic_vector (11 downto 0);
  signal bitMapLine  : std_logic_vector (7 downto 0);
  signal bitMapPixel : std_logic;

  type   romType is array (0 to 2**12-1) of std_logic_vector (7 downto 0);  -- OJO: los pixeles est�n ubicados de izq. a der. y da igual que se cambie el range
  signal rom : romType := (
    X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- null
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- space
    X"00", X"00", X"00", X"18", X"3c", X"3c", X"3c", X"18", X"18", X"00", X"18", X"18", X"00", X"00", X"00", X"00",    -- !
    X"00", X"00", X"c6", X"c6", X"c6", X"44", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- "
    X"00", X"00", X"00", X"6c", X"6c", X"fe", X"6c", X"6c", X"6c", X"fe", X"6c", X"6c", X"00", X"00", X"00", X"00",    -- #
    X"00", X"18", X"18", X"7c", X"c6", X"c2", X"c0", X"7c", X"06", X"86", X"c6", X"7c", X"18", X"18", X"00", X"00",    -- $
    X"00", X"00", X"00", X"00", X"00", X"c3", X"c6", X"0c", X"18", X"30", X"63", X"c3", X"00", X"00", X"00", X"00",    -- %
    X"00", X"00", X"00", X"38", X"6c", X"6c", X"38", X"76", X"dc", X"cc", X"cc", X"76", X"00", X"00", X"00", X"00",    -- &
    X"00", X"00", X"30", X"30", X"30", X"60", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- �
    X"00", X"00", X"00", X"18", X"30", X"60", X"60", X"60", X"60", X"60", X"30", X"18", X"00", X"00", X"00", X"00",    -- (
    X"00", X"00", X"00", X"18", X"0c", X"06", X"06", X"06", X"06", X"06", X"0c", X"18", X"00", X"00", X"00", X"00",    -- )
    X"00", X"00", X"00", X"00", X"00", X"6c", X"38", X"fe", X"38", X"6c", X"00", X"00", X"00", X"00", X"00", X"00",    -- *
    X"00", X"00", X"00", X"00", X"18", X"18", X"18", X"7e", X"18", X"18", X"18", X"00", X"00", X"00", X"00", X"00",    -- +  
    X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"18", X"18", X"18", X"30", X"00", X"00", X"00",    -- ,
    X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"fe", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- -
    X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"18", X"18", X"00", X"00", X"00", X"00",    -- . 
    X"00", X"00", X"00", X"02", X"06", X"0c", X"18", X"30", X"60", X"c0", X"80", X"00", X"00", X"00", X"00", X"00",    -- /
    X"00", X"00", X"00", X"7c", X"c6", X"ce", X"de", X"f6", X"e6", X"c6", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- 0
    X"00", X"00", X"00", X"18", X"38", X"78", X"18", X"18", X"18", X"18", X"18", X"7e", X"00", X"00", X"00", X"00",    -- 1
    X"00", X"00", X"00", X"7c", X"c6", X"06", X"0c", X"18", X"30", X"60", X"c6", X"fe", X"00", X"00", X"00", X"00",    -- 2
    X"00", X"00", X"00", X"7c", X"c6", X"06", X"06", X"3c", X"06", X"06", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- 3
    X"00", X"00", X"00", X"0c", X"1c", X"3c", X"6c", X"cc", X"fe", X"0c", X"0c", X"1e", X"00", X"00", X"00", X"00",    -- 4
    X"00", X"00", X"00", X"fe", X"c0", X"c0", X"c0", X"fc", X"06", X"06", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- 5
    X"00", X"00", X"00", X"38", X"60", X"c0", X"c0", X"fc", X"c6", X"c6", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- 6
    X"00", X"00", X"00", X"fe", X"c6", X"06", X"0c", X"18", X"30", X"30", X"30", X"30", X"00", X"00", X"00", X"00",    -- 7
    X"00", X"00", X"00", X"7c", X"c6", X"c6", X"c6", X"7c", X"c6", X"c6", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- 8
    X"00", X"00", X"00", X"7c", X"c6", X"c6", X"c6", X"7e", X"06", X"06", X"0c", X"78", X"00", X"00", X"00", X"00",    -- 9
    X"00", X"00", X"00", X"00", X"18", X"18", X"00", X"00", X"00", X"18", X"18", X"00", X"00", X"00", X"00", X"00",    -- :
    X"00", X"00", X"00", X"00", X"18", X"18", X"00", X"00", X"00", X"18", X"18", X"30", X"00", X"00", X"00", X"00",    -- ;
    X"00", X"00", X"00", X"06", X"0c", X"18", X"30", X"60", X"30", X"18", X"0c", X"06", X"00", X"00", X"00", X"00",    -- <
    X"00", X"00", X"00", X"00", X"00", X"00", X"7e", X"00", X"00", X"7e", X"00", X"00", X"00", X"00", X"00", X"00",    -- =
    X"00", X"00", X"00", X"60", X"30", X"18", X"0c", X"06", X"0c", X"18", X"30", X"60", X"00", X"00", X"00", X"00",    -- >
    X"00", X"00", X"00", X"7c", X"c6", X"c6", X"0c", X"18", X"18", X"00", X"18", X"18", X"00", X"00", X"00", X"00",    -- ?  
    X"00", X"00", X"00", X"7c", X"c6", X"c6", X"de", X"de", X"de", X"dc", X"c0", X"7c", X"00", X"00", X"00", X"00",    -- @
    X"00", X"00", X"00", X"10", X"38", X"6c", X"c6", X"c6", X"fe", X"c6", X"c6", X"c6", X"00", X"00", X"00", X"00",    -- A
    X"00", X"00", X"00", X"fc", X"66", X"66", X"66", X"7c", X"66", X"66", X"66", X"fc", X"00", X"00", X"00", X"00",    -- B
    X"00", X"00", X"00", X"3c", X"66", X"c2", X"c0", X"c0", X"c0", X"c2", X"66", X"3c", X"00", X"00", X"00", X"00",    -- C
    X"00", X"00", X"00", X"f8", X"6c", X"66", X"66", X"66", X"66", X"66", X"6c", X"f8", X"00", X"00", X"00", X"00",    -- D
    X"00", X"00", X"00", X"fe", X"66", X"62", X"68", X"78", X"68", X"62", X"66", X"fe", X"00", X"00", X"00", X"00",    -- E
    X"00", X"00", X"00", X"fe", X"66", X"62", X"68", X"78", X"68", X"60", X"60", X"f0", X"00", X"00", X"00", X"00",    -- F
    X"00", X"00", X"00", X"3c", X"66", X"c2", X"c0", X"c0", X"de", X"c6", X"66", X"3a", X"00", X"00", X"00", X"00",    -- G
    X"00", X"00", X"00", X"c6", X"c6", X"c6", X"c6", X"fe", X"c6", X"c6", X"c6", X"c6", X"00", X"00", X"00", X"00",    -- H
    X"00", X"00", X"00", X"3c", X"18", X"18", X"18", X"18", X"18", X"18", X"18", X"3c", X"00", X"00", X"00", X"00",    -- I
    X"00", X"00", X"00", X"1e", X"0c", X"0c", X"0c", X"0c", X"0c", X"cc", X"cc", X"78", X"00", X"00", X"00", X"00",    -- J
    X"00", X"00", X"00", X"e6", X"66", X"6c", X"6c", X"78", X"6c", X"6c", X"66", X"e6", X"00", X"00", X"00", X"00",    -- K
    X"00", X"00", X"00", X"f0", X"60", X"60", X"60", X"60", X"60", X"62", X"66", X"fe", X"00", X"00", X"00", X"00",    -- L
    X"00", X"00", X"00", X"c6", X"ee", X"fe", X"d6", X"c6", X"c6", X"c6", X"c6", X"c6", X"00", X"00", X"00", X"00",    -- M
    X"00", X"00", X"00", X"c6", X"e6", X"f6", X"fe", X"de", X"ce", X"c6", X"c6", X"c6", X"00", X"00", X"00", X"00",    -- N
    X"00", X"00", X"00", X"38", X"6c", X"c6", X"c6", X"c6", X"c6", X"c6", X"6c", X"38", X"00", X"00", X"00", X"00",    -- O
    X"00", X"00", X"00", X"fc", X"66", X"66", X"66", X"7c", X"60", X"60", X"60", X"f0", X"00", X"00", X"00", X"00",    -- P
    X"00", X"00", X"00", X"7c", X"c6", X"c6", X"c6", X"d6", X"de", X"7c", X"0c", X"0e", X"00", X"00", X"00", X"00",    -- Q
    X"00", X"00", X"00", X"fc", X"66", X"66", X"66", X"7c", X"6c", X"66", X"66", X"e6", X"00", X"00", X"00", X"00",    -- R
    X"00", X"00", X"00", X"7c", X"c6", X"c6", X"60", X"38", X"0c", X"c6", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- S
    X"00", X"00", X"00", X"7e", X"5a", X"18", X"18", X"18", X"18", X"18", X"18", X"3c", X"00", X"00", X"00", X"00",    -- T
    X"00", X"00", X"00", X"c6", X"c6", X"c6", X"c6", X"c6", X"c6", X"c6", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- U
    X"00", X"00", X"00", X"c6", X"c6", X"c6", X"c6", X"c6", X"c6", X"6c", X"38", X"10", X"00", X"00", X"00", X"00",    -- V
    X"00", X"00", X"00", X"c6", X"c6", X"c6", X"c6", X"c6", X"d6", X"fe", X"ee", X"c6", X"00", X"00", X"00", X"00",    -- W
    X"00", X"00", X"00", X"c6", X"c6", X"c6", X"6c", X"38", X"6c", X"c6", X"c6", X"c6", X"00", X"00", X"00", X"00",    -- X
    X"00", X"00", X"00", X"c6", X"c6", X"c6", X"6c", X"38", X"38", X"38", X"38", X"7c", X"00", X"00", X"00", X"00",    -- Y
    X"00", X"00", X"00", X"fe", X"c6", X"8c", X"18", X"30", X"60", X"c2", X"c6", X"fe", X"00", X"00", X"00", X"00",    -- Z
    X"00", X"00", X"00", X"3c", X"30", X"30", X"30", X"30", X"30", X"30", X"30", X"3c", X"00", X"00", X"00", X"00",    -- [
    X"00", X"00", X"00", X"80", X"c0", X"e0", X"70", X"38", X"1c", X"0e", X"06", X"02", X"00", X"00", X"00", X"00",    -- \
    X"00", X"00", X"00", X"3c", X"0c", X"0c", X"0c", X"0c", X"0c", X"0c", X"0c", X"3c", X"00", X"00", X"00", X"00",    -- ]
    X"00", X"10", X"38", X"6c", X"c6", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- ^
    X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"fe", X"00", X"00",    -- _   
    X"00", X"00", X"30", X"30", X"18", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- `
    X"00", X"00", X"00", X"00", X"00", X"00", X"78", X"0c", X"7c", X"cc", X"cc", X"76", X"00", X"00", X"00", X"00",    -- a
    X"00", X"00", X"00", X"e0", X"60", X"60", X"78", X"6c", X"66", X"66", X"66", X"dc", X"00", X"00", X"00", X"00",    -- b
    X"00", X"00", X"00", X"00", X"00", X"00", X"7c", X"c6", X"c0", X"c0", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- c
    X"00", X"00", X"00", X"1c", X"0c", X"0c", X"3c", X"6c", X"cc", X"cc", X"cc", X"76", X"00", X"00", X"00", X"00",    -- d
    X"00", X"00", X"00", X"00", X"00", X"00", X"7c", X"c6", X"fe", X"c0", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- e
    X"00", X"00", X"00", X"1c", X"36", X"32", X"30", X"7c", X"30", X"30", X"30", X"78", X"00", X"00", X"00", X"00",    -- f
    X"00", X"00", X"00", X"00", X"00", X"00", X"76", X"cc", X"cc", X"cc", X"7c", X"0c", X"cc", X"78", X"00", X"00",    -- g
    X"00", X"00", X"00", X"e0", X"60", X"60", X"6c", X"76", X"66", X"66", X"66", X"e6", X"00", X"00", X"00", X"00",    -- h
    X"00", X"00", X"00", X"18", X"18", X"00", X"38", X"18", X"18", X"18", X"18", X"3c", X"00", X"00", X"00", X"00",    -- i
    X"00", X"00", X"00", X"06", X"06", X"00", X"0e", X"06", X"06", X"06", X"06", X"66", X"66", X"3c", X"00", X"00",    -- j
    X"00", X"00", X"00", X"e0", X"60", X"60", X"66", X"6c", X"78", X"6c", X"66", X"e6", X"00", X"00", X"00", X"00",    -- k
    X"00", X"00", X"00", X"38", X"18", X"18", X"18", X"18", X"18", X"18", X"18", X"3c", X"00", X"00", X"00", X"00",    -- l
    X"00", X"00", X"00", X"00", X"00", X"00", X"44", X"fe", X"d6", X"d6", X"d6", X"d6", X"00", X"00", X"00", X"00",    -- m
    X"00", X"00", X"00", X"00", X"00", X"00", X"dc", X"66", X"66", X"66", X"66", X"66", X"00", X"00", X"00", X"00",    -- n
    X"00", X"00", X"00", X"00", X"00", X"00", X"7c", X"c6", X"c6", X"c6", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- o
    X"00", X"00", X"00", X"00", X"00", X"00", X"dc", X"66", X"66", X"66", X"7c", X"60", X"60", X"f0", X"00", X"00",    -- p
    X"00", X"00", X"00", X"00", X"00", X"00", X"76", X"cc", X"cc", X"cc", X"7c", X"0c", X"0c", X"1e", X"00", X"00",    -- q
    X"00", X"00", X"00", X"00", X"00", X"00", X"dc", X"76", X"66", X"60", X"60", X"f0", X"00", X"00", X"00", X"00",    -- r
    X"00", X"00", X"00", X"00", X"00", X"00", X"7c", X"c6", X"70", X"1c", X"c6", X"7c", X"00", X"00", X"00", X"00",    -- s
    X"00", X"00", X"00", X"10", X"30", X"30", X"fc", X"30", X"30", X"30", X"36", X"1c", X"00", X"00", X"00", X"00",    -- t
    X"00", X"00", X"00", X"00", X"00", X"00", X"cc", X"cc", X"cc", X"cc", X"cc", X"76", X"00", X"00", X"00", X"00",    -- u
    X"00", X"00", X"00", X"00", X"00", X"00", X"c6", X"c6", X"c6", X"6c", X"38", X"10", X"00", X"00", X"00", X"00",    -- v 
    X"00", X"00", X"00", X"00", X"00", X"00", X"c6", X"c6", X"c6", X"d6", X"fe", X"6c", X"00", X"00", X"00", X"00",    -- w
    X"00", X"00", X"00", X"00", X"00", X"00", X"c6", X"6c", X"38", X"38", X"6c", X"c6", X"00", X"00", X"00", X"00",    -- x
    X"00", X"00", X"00", X"00", X"00", X"00", X"c6", X"c6", X"c6", X"c6", X"7e", X"06", X"0c", X"78", X"00", X"00",    -- y
    X"00", X"00", X"00", X"00", X"00", X"00", X"fe", X"cc", X"18", X"30", X"66", X"fe", X"00", X"00", X"00", X"00",    -- z
    X"00", X"00", X"00", X"0e", X"18", X"18", X"18", X"70", X"18", X"18", X"18", X"0e", X"00", X"00", X"00", X"00",    -- {
    X"00", X"00", X"00", X"18", X"18", X"18", X"18", X"00", X"18", X"18", X"18", X"18", X"00", X"00", X"00", X"00",    -- |
    X"00", X"00", X"00", X"70", X"18", X"18", X"18", X"0e", X"18", X"18", X"18", X"70", X"00", X"00", X"00", X"00",    -- }
    X"00", X"00", X"00", X"76", X"dc", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00", X"00",    -- ~
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"00", X"76", X"dc", X"00", X"00", X"dc", X"66", X"66", X"66", X"66", X"66", X"00", X"00", X"00", X"00",    -- �
    X"00", X"00", X"76", X"dc", X"00", X"00", X"dc", X"66", X"66", X"66", X"66", X"66", X"00", X"00", X"00", X"00",    -- �
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00",    -- empty
    X"00", X"7e", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"42", X"7e", X"00"     -- empty
  );

begin

  screenInteface: vgaRefresher
    generic map ( FREQ_DIV => 1 )
    port map ( clk => clk, line => line, pixel => pixel, R => color(11 downto 8), G => color(7 downto 4), B => color(3 downto 0), hSync => hSync, vSync => vSync, RGB => RGB );
  
  colInt  <= pixel(9 downto 3);
  uColInt <= pixel(2 downto 0);
  
  rowInt  <= line(8 downto 4);
  uRowInt <= line(3 downto 0);
  
  col  <= colInt;
  uCol <= uColInt;
  
  row  <= rowInt;
  uRow <= uRowInt;
  
------------------  

  we        <= dataRdy or clearing;
  ramWrData <= (others => '0') when clearing='1' else char;      
  ramWrAddr <= std_logic_vector(clearY) & std_logic_vector(clearX) when clearing='0' else y & x; 
  ramRdAddr <= rowInt & colInt;
  
  process (clk)
  begin
    if rising_edge(clk) then
      if we='1' then
        ram( to_integer(unsigned(ramWrAddr)) ) <= ramWrData;
      end if; 
      asciiCode <= ram( to_integer(unsigned(ramRdAddr)) );
    end if;
  end process;
  
------------------  
  
  romAddr <= asciiCode & uRowInt;
 
  process (clk)
  begin
    if rising_edge(clk) then
      bitMapLine <= rom( to_integer(unsigned(romAddr))) ;
    end if;
  end process;

------------------  

  with uColInt select
    bitMapPixel <= 
      bitMapLine(7) when "000",
      bitMapLine(6) when "001",
      bitMapLine(5) when "010",
      bitMapLine(4) when "011",
      bitMapLine(3) when "100",
      bitMapLine(2) when "101",
      bitMapLine(1) when "110",
      bitMapLine(0) when others;
      

  color <= FGCOLOR when bitMapPixel='1' else BGCOLOR;  
  
------------------  

  clearCounters:
  process (clk, clearX, clearY, clear)
  begin
    if clearX = (clearX'range => '1') and clearY = (clearY'range => '1') then
      clearing <= '0';
    else
      clearing <= '0';
    end if;
    
    
    if rising_edge(clk) then
      if clear='1' or clearing='1' then
        if clearX = (clearX'range => '1') then
          clearX <= (others => '0');
          if clearY = (clearY'range => '1') then
            clearY <= (others => '0');
          else
            clearY <= clearY + 1;
          end if;
        end if;
      end if;
    end if;
  end process; 
  
  clearing <= '1' when (clear = '1') or (clearX /= (clearX'range => '1') or clearY /= (clearY'range => '1')) else '0';

end syn;

