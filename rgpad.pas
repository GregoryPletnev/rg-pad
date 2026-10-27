{ rgpad: RG35XXH gamepad -> virtual keyboard + mouse (uinput).

  - plain buttons map to keys / mouse buttons / actions ([buttons])
  - left stick direction + X/A/B/Y types characters (chords, [layer ...])
  - right stick moves the mouse pointer ([mouse])
  - a button combo toggles between mapping and raw gamepad passthrough

  Usage: rgpad [-c /etc/rgpad.conf] [-v] }
program rgpad;

{$mode objfpc}{$H+}

uses
  BaseUnix, SysUtils, Classes, Math;

const
  EV_SYN = 0; EV_KEY = 1; EV_REL = 2; EV_ABS = 3; EV_REP = $14;
  SYN_REPORT = 0;
  REL_X = 0; REL_Y = 1; REL_WHEEL = 8;
  ABS_X = 0; ABS_Y = 1; ABS_RX = 3; ABS_RY = 4;
  BTN_LEFT = $110; BTN_RIGHT = $111; BTN_MIDDLE = $112;
  KEY_LEFTSHIFT = 42;
  BUS_VIRTUAL = 6;

  { aarch64 _IOC encoding: dir<<30 | size<<16 | type<<8 | nr }
  EVIOCGNAME256 = $81004506;
  EVIOCGRAB     = $40044590;
  EVIOCGABS0    = $80184540;
  UI_SET_EVBIT  = $40045564;
  UI_SET_KEYBIT = $40045565;
  UI_SET_RELBIT = $40045566;
  UI_DEV_SETUP  = $405C5503;
  UI_DEV_CREATE = $5501;
  UI_DEV_DESTROY = $5502;

  { physical buttons }
  BUTTON_COUNT = 17;
  ButtonNames: array[0..BUTTON_COUNT - 1] of string = (
    'x', 'a', 'b', 'y', 'l1', 'r1', 'l2', 'r2', 'select', 'start', 'menu',
    'l3', 'r3', 'up', 'down', 'left', 'right');
  { the DTS labels X/Y the other way round: the button printed X sends
    BTN_WEST ($134), the one printed Y sends BTN_NORTH ($133) }
  ButtonCodes: array[0..BUTTON_COUNT - 1] of Word = (
    $134, $131, $130, $133, $136, $137, $138, $139, $13a, $13b, $13c,
    $13d, $13e, $220, $221, $222, $223);
  CHORD_BUTTONS = 4;   { indexes 0..3: X A B Y, clockwise from the top }

  DIR_CENTER = 8;
  DirNames: array[0..8] of string = (
    'e', 'ne', 'n', 'nw', 'w', 'sw', 's', 'se', 'center');

type
  TInputEvent = packed record
    Sec, USec: Int64;
    Typ, Code: Word;
    Value: LongInt;
  end;

  TAbsInfo = packed record
    Value, Minimum, Maximum, Fuzz, Flat, Resolution: LongInt;
  end;

  TUInputSetup = packed record
    BusType, Vendor, Product, Version: Word;
    Name: array[0..79] of Char;
    FFEffectsMax: LongWord;
  end;

  TActKind = (akNone, akKey, akMouse, akLayer);

  TKeyTok = record
    Code: Integer;     { 0 = none }
    Shift: Boolean;
  end;

  TLayer = record
    Name: string;
    Tok: array[0..8, 0..CHORD_BUTTONS - 1] of TKeyTok;
  end;

  TAxis = record
    Center, Half: Double;
    Value: Integer;
    Invert: Boolean;
  end;

  TNamedKey = record
    N: string;
    C: Word;
  end;

const
  NamedKeys: array[0..56] of TNamedKey = (
    (N: 'ESC'; C: 1), (N: 'MINUS'; C: 12), (N: 'EQUAL'; C: 13),
    (N: 'BACKSPACE'; C: 14), (N: 'TAB'; C: 15), (N: 'LEFTBRACE'; C: 26),
    (N: 'RIGHTBRACE'; C: 27), (N: 'ENTER'; C: 28), (N: 'LEFTCTRL'; C: 29),
    (N: 'CTRL'; C: 29), (N: 'SEMICOLON'; C: 39), (N: 'APOSTROPHE'; C: 40),
    (N: 'GRAVE'; C: 41), (N: 'LEFTSHIFT'; C: 42), (N: 'SHIFT'; C: 42),
    (N: 'BACKSLASH'; C: 43), (N: 'COMMA'; C: 51), (N: 'DOT'; C: 52),
    (N: 'SLASH'; C: 53), (N: 'RIGHTSHIFT'; C: 54), (N: 'LEFTALT'; C: 56),
    (N: 'ALT'; C: 56), (N: 'SPACE'; C: 57), (N: 'CAPSLOCK'; C: 58),
    (N: 'F1'; C: 59), (N: 'F2'; C: 60), (N: 'F3'; C: 61), (N: 'F4'; C: 62),
    (N: 'F5'; C: 63), (N: 'F6'; C: 64), (N: 'F7'; C: 65), (N: 'F8'; C: 66),
    (N: 'F9'; C: 67), (N: 'F10'; C: 68), (N: 'F11'; C: 87), (N: 'F12'; C: 88),
    (N: 'RIGHTCTRL'; C: 97), (N: 'SYSRQ'; C: 99), (N: 'RIGHTALT'; C: 100),
    (N: 'HOME'; C: 102), (N: 'UP'; C: 103), (N: 'PAGEUP'; C: 104),
    (N: 'LEFT'; C: 105), (N: 'RIGHT'; C: 106), (N: 'END'; C: 107),
    (N: 'DOWN'; C: 108), (N: 'PAGEDOWN'; C: 109), (N: 'INSERT'; C: 110),
    (N: 'DELETE'; C: 111), (N: 'MUTE'; C: 113), (N: 'VOLUMEDOWN'; C: 114),
    (N: 'VOLUMEUP'; C: 115), (N: 'POWER'; C: 116), (N: 'PAUSE'; C: 119),
    (N: 'LEFTMETA'; C: 125), (N: 'META'; C: 125), (N: 'COMPOSE'; C: 127));

  LetterCodes: array['a'..'z'] of Byte = (
    30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
    49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44);
  PlainSyms   = '-=[];''`\,./';
  ShiftedSyms = '_+{}:"~|<>?';
  SymCodes: array[1..11] of Byte = (12, 13, 26, 27, 39, 40, 41, 43, 51, 52, 53);
  ShiftedDigits = ')!@#$%^&*(';

var
  Cfg: TStringList;          { "section.key=value" }
  LayerSections: TStringList;
  Layers: array of TLayer;
  Act: array[0..BUTTON_COUNT - 1] of record
    Kind: TActKind;
    Code: Integer;
  end;
  Pressed: array[0..BUTTON_COUNT - 1] of TKeyTok;   { what a held button emitted }
  Held: array[0..BUTTON_COUNT - 1] of Boolean;
  ToggleA, ToggleB: Integer;
  Axes: array[0..3] of TAxis;  { LX LY RX RY }
  ChordThreshold, MouseDeadzone, MouseSpeed, MouseAccel: Double;
  MouseRate: Integer;
  AccX, AccY: Double;
  LedName: string;
  GamepadFd, JoystickFd, KbdFd, MouseFd: cint;
  Layer, ShiftCount: Integer;
  Active, Verbose, Terminated: Boolean;

{ ---------- config ---------- }

procedure Die(const Msg: string);
begin
  WriteLn(StdErr, 'rgpad: ', Msg);
  Halt(1);
end;

procedure Log(const Msg: string);
begin
  if Verbose then
    WriteLn(Msg);
end;

procedure LoadConfig(const FileName: string);
var
  Lines: TStringList;
  S, Section, Key: string;
  I, P: Integer;
begin
  Cfg := TStringList.Create;
  LayerSections := TStringList.Create;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    Section := '';
    for I := 0 to Lines.Count - 1 do
    begin
      S := Trim(Lines[I]);
      if (S = '') or (S[1] in ['#', ';']) then
        Continue;
      if S[1] = '[' then
      begin
        Section := Trim(Copy(S, 2, Pos(']', S) - 2));
        if LowerCase(Copy(Section, 1, 6)) = 'layer ' then
        begin
          { layer names are case-sensitive ("abc" vs "ABC"): key them by index }
          LayerSections.Add(Trim(Copy(Section, 7, MaxInt)));
          Section := 'layer#' + IntToStr(LayerSections.Count - 1);
        end
        else
          Section := LowerCase(Section);
        Continue;
      end;
      P := Pos('=', S);
      if P = 0 then
        Die(Format('%s:%d: expected key = value', [FileName, I + 1]));
      Key := LowerCase(Trim(Copy(S, 1, P - 1)));
      Cfg.Values[Section + '.' + Key] := Trim(Copy(S, P + 1, MaxInt));
    end;
  finally
    Lines.Free;
  end;
end;

function CfgStr(const Sec, Key, Def: string): string;
begin
  Result := Cfg.Values[Sec + '.' + Key];
  if Result = '' then
    Result := Def;
end;

function CfgFloat(const Sec, Key: string; Def: Double): Double;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := StrToFloatDef(CfgStr(Sec, Key, ''), Def, FS);
end;

function CfgBool(const Sec, Key: string; Def: Boolean): Boolean;
begin
  Result := StrToIntDef(CfgStr(Sec, Key, IntToStr(Ord(Def))), Ord(Def)) <> 0;
end;

function ButtonIndex(const Name: string): Integer;
var
  I: Integer;
begin
  for I := 0 to BUTTON_COUNT - 1 do
    if ButtonNames[I] = LowerCase(Name) then
      Exit(I);
  Result := -1;
end;

function KeyByName(Name: string): Integer;
var
  I: Integer;
begin
  Name := UpperCase(Name);
  if Copy(Name, 1, 4) = 'KEY_' then
    Delete(Name, 1, 4);
  for I := Low(NamedKeys) to High(NamedKeys) do
    if NamedKeys[I].N = Name then
      Exit(NamedKeys[I].C);
  Result := StrToIntDef(Name, 0);
end;

function CharToKey(C: Char; out Tok: TKeyTok): Boolean;
var
  P: Integer;
begin
  Tok.Shift := False;
  Tok.Code := 0;
  case C of
    'a'..'z': Tok.Code := LetterCodes[C];
    'A'..'Z': begin Tok.Code := LetterCodes[Chr(Ord(C) + 32)]; Tok.Shift := True; end;
    '1'..'9': Tok.Code := Ord(C) - Ord('1') + 2;
    '0': Tok.Code := 11;
    ' ': Tok.Code := 57;
  else
    P := Pos(C, PlainSyms);
    if P > 0 then
      Tok.Code := SymCodes[P]
    else
    begin
      P := Pos(C, ShiftedSyms);
      if P > 0 then
      begin
        Tok.Code := SymCodes[P];
        Tok.Shift := True;
      end
      else
      begin
        P := Pos(C, ShiftedDigits);
        if P > 0 then
        begin
          Tok.Code := P;   { '!' -> KEY_1 (2) ... '(' -> KEY_9 (10), ')' -> KEY_0 }
          if P = 1 then
            Tok.Code := 11;
          Tok.Shift := True;
        end;
      end;
    end;
  end;
  Result := Tok.Code <> 0;
end;

function ParseToken(const S: string): TKeyTok;
begin
  if Length(S) = 1 then
  begin
    if not CharToKey(S[1], Result) then
      Die('cannot type character "' + S + '" with the US layout');
  end
  else
  begin
    Result.Shift := False;
    Result.Code := KeyByName(S);
    if Result.Code = 0 then
      Die('unknown key name "' + S + '"');
  end;
end;

procedure SplitWords(const S: string; Words: TStringList);
var
  I: Integer;
  W: string;
begin
  Words.Clear;
  W := '';
  for I := 1 to Length(S) do
    if S[I] in [' ', #9] then
    begin
      if W <> '' then
        Words.Add(W);
      W := '';
    end
    else
      W := W + S[I];
  if W <> '' then
    Words.Add(W);
end;

procedure SetupMapping;
var
  I, D, B: Integer;
  V: string;
  Words: TStringList;
begin
  for I := 0 to BUTTON_COUNT - 1 do
  begin
    V := CfgStr('buttons', ButtonNames[I], '');
    Act[I].Kind := akNone;
    if V = '' then
      Continue;
    if LowerCase(V) = '@layer' then
      Act[I].Kind := akLayer
    else if UpperCase(V) = 'BTN_LEFT' then
      begin Act[I].Kind := akMouse; Act[I].Code := BTN_LEFT; end
    else if UpperCase(V) = 'BTN_RIGHT' then
      begin Act[I].Kind := akMouse; Act[I].Code := BTN_RIGHT; end
    else if UpperCase(V) = 'BTN_MIDDLE' then
      begin Act[I].Kind := akMouse; Act[I].Code := BTN_MIDDLE; end
    else
    begin
      Act[I].Kind := akKey;
      Act[I].Code := KeyByName(V);
      if Act[I].Code = 0 then
        Die('[buttons] ' + ButtonNames[I] + ': unknown key "' + V + '"');
    end;
  end;

  V := CfgStr('general', 'toggle', 'start+menu');
  ToggleA := ButtonIndex(Copy(V, 1, Pos('+', V) - 1));
  ToggleB := ButtonIndex(Copy(V, Pos('+', V) + 1, MaxInt));
  if (ToggleA < 0) or (ToggleB < 0) then
    Die('[general] toggle: expected button+button');

  if LayerSections.Count = 0 then
    Die('no [layer ...] sections');
  SetLength(Layers, LayerSections.Count);
  Words := TStringList.Create;
  try
    for I := 0 to LayerSections.Count - 1 do
    begin
      Layers[I].Name := LayerSections[I];
      for D := 0 to 8 do
      begin
        for B := 0 to CHORD_BUTTONS - 1 do
          Layers[I].Tok[D, B].Code := 0;
        SplitWords(CfgStr('layer#' + IntToStr(I), DirNames[D], ''), Words);
        if Words.Count > CHORD_BUTTONS then
          Die(Format('[layer %s] %s: more than 4 tokens', [LayerSections[I], DirNames[D]]));
        for B := 0 to Words.Count - 1 do
          Layers[I].Tok[D, B] := ParseToken(Words[B]);
      end;
    end;
  finally
    Words.Free;
  end;

  ChordThreshold := CfgFloat('left_stick', 'threshold', 0.5);
  Axes[0].Invert := CfgBool('left_stick', 'invert_x', False);
  Axes[1].Invert := CfgBool('left_stick', 'invert_y', False);
  MouseDeadzone := CfgFloat('mouse', 'deadzone', 0.12);
  MouseSpeed := CfgFloat('mouse', 'speed', 10);
  MouseAccel := CfgFloat('mouse', 'accel', 2.0);
  MouseRate := Max(10, Round(CfgFloat('mouse', 'rate', 100)));
  Axes[2].Invert := CfgBool('mouse', 'invert_x', False);
  Axes[3].Invert := CfgBool('mouse', 'invert_y', False);
  LedName := CfgStr('general', 'led', '');
end;

{ ---------- devices ---------- }

function FindDevice(const Name: string): cint;
var
  I: Integer;
  Fd: cint;
  Buf: array[0..255] of Char;
begin
  for I := 0 to 63 do
  begin
    Fd := FpOpen('/dev/input/event' + IntToStr(I), O_RDONLY or O_NONBLOCK);
    if Fd < 0 then
      Continue;
    FillChar(Buf, SizeOf(Buf), 0);
    if (FpIOCtl(Fd, EVIOCGNAME256, @Buf) >= 0) and (StrPas(Buf) = Name) then
      Exit(Fd);
    FpClose(Fd);
  end;
  Result := -1;
end;

procedure SetBit(Fd: cint; Req: TIOCtlRequest; Bit: PtrUInt);
begin
  if FpIOCtl(Fd, Req, Pointer(Bit)) < 0 then
    Die('uinput ioctl failed: ' + SysErrorMessage(fpgeterrno));
end;

function CreateUInput(const Name: string; Mouse: Boolean): cint;
var
  Setup: TUInputSetup;
  I: Integer;
begin
  Result := FpOpen('/dev/uinput', O_WRONLY or O_NONBLOCK);
  if Result < 0 then
    Die('cannot open /dev/uinput: ' + SysErrorMessage(fpgeterrno));
  SetBit(Result, UI_SET_EVBIT, EV_KEY);
  if Mouse then
  begin
    SetBit(Result, UI_SET_KEYBIT, BTN_LEFT);
    SetBit(Result, UI_SET_KEYBIT, BTN_RIGHT);
    SetBit(Result, UI_SET_KEYBIT, BTN_MIDDLE);
    SetBit(Result, UI_SET_EVBIT, EV_REL);
    SetBit(Result, UI_SET_RELBIT, REL_X);
    SetBit(Result, UI_SET_RELBIT, REL_Y);
    SetBit(Result, UI_SET_RELBIT, REL_WHEEL);
  end
  else
  begin
    SetBit(Result, UI_SET_EVBIT, EV_REP);   { kernel autorepeat for held keys }
    for I := 1 to 248 do
      SetBit(Result, UI_SET_KEYBIT, I);
  end;
  FillChar(Setup, SizeOf(Setup), 0);
  Setup.BusType := BUS_VIRTUAL;
  Setup.Vendor := $1209;
  Setup.Product := $35A7 + Ord(Mouse);
  Setup.Version := 1;
  StrPLCopy(Setup.Name, Name, High(Setup.Name));
  if (FpIOCtl(Result, UI_DEV_SETUP, @Setup) < 0) or
     (FpIOCtl(Result, UI_DEV_CREATE, nil) < 0) then
    Die('cannot create uinput device: ' + SysErrorMessage(fpgeterrno));
end;

procedure Emit(Fd: cint; Typ, Code: Word; Value: LongInt);
var
  Ev: TInputEvent;
begin
  FillChar(Ev, SizeOf(Ev), 0);
  Ev.Typ := Typ;
  Ev.Code := Code;
  Ev.Value := Value;
  FpWrite(Fd, Ev, SizeOf(Ev));
end;

procedure Syn(Fd: cint);
begin
  Emit(Fd, EV_SYN, SYN_REPORT, 0);
end;

procedure InitAxis(Idx: Integer; Code: Word; Calibrate: Boolean);
var
  Info: TAbsInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  if FpIOCtl(JoystickFd, EVIOCGABS0 + Code, @Info) < 0 then
    Die('EVIOCGABS failed');
  Axes[Idx].Half := Max(1, (Info.Maximum - Info.Minimum) / 2);
  if Calibrate then
    Axes[Idx].Center := Info.Value
  else
    Axes[Idx].Center := (Info.Maximum + Info.Minimum) / 2;
  Axes[Idx].Value := Info.Value;
end;

function AxisNorm(Idx: Integer): Double;
begin
  Result := EnsureRange((Axes[Idx].Value - Axes[Idx].Center) / Axes[Idx].Half, -1, 1);
  if Axes[Idx].Invert then
    Result := -Result;
end;

procedure Grab(On: Boolean);
begin
  FpIOCtl(GamepadFd, EVIOCGRAB, Pointer(PtrUInt(Ord(On))));
  FpIOCtl(JoystickFd, EVIOCGRAB, Pointer(PtrUInt(Ord(On))));
end;

procedure WriteSys(const Path, S: string);
var
  Fd: cint;
begin
  Fd := FpOpen(Path, O_WRONLY);
  if Fd >= 0 then
  begin
    FpWrite(Fd, PChar(S)^, Length(S));
    FpClose(Fd);
  end;
end;

procedure UpdateLed;
var
  Base: string;
begin
  if LedName = '' then
    Exit;
  Base := '/sys/class/leds/' + LedName + '/';
  if not Active then
    WriteSys(Base + 'trigger', 'heartbeat')
  else if Layer = 0 then
  begin
    WriteSys(Base + 'trigger', 'none');
    WriteSys(Base + 'brightness', '0');
  end
  else if Layer = 1 then
  begin
    WriteSys(Base + 'trigger', 'none');
    WriteSys(Base + 'brightness', '1');
  end
  else
    WriteSys(Base + 'trigger', 'timer');
end;

{ ---------- mapping ---------- }

procedure KeyDown(const Tok: TKeyTok);
begin
  if Tok.Shift then
  begin
    Inc(ShiftCount);
    if ShiftCount = 1 then
      Emit(KbdFd, EV_KEY, KEY_LEFTSHIFT, 1);
  end;
  Emit(KbdFd, EV_KEY, Tok.Code, 1);
  Syn(KbdFd);
end;

procedure KeyUp(const Tok: TKeyTok);
begin
  Emit(KbdFd, EV_KEY, Tok.Code, 0);
  if Tok.Shift then
  begin
    Dec(ShiftCount);
    if ShiftCount = 0 then
      Emit(KbdFd, EV_KEY, KEY_LEFTSHIFT, 0);
  end;
  Syn(KbdFd);
end;

procedure ReleaseAll;
var
  I: Integer;
begin
  for I := 0 to BUTTON_COUNT - 1 do
    if Pressed[I].Code <> 0 then
    begin
      if Pressed[I].Code >= BTN_LEFT then
      begin
        Emit(MouseFd, EV_KEY, Pressed[I].Code, 0);
        Syn(MouseFd);
      end
      else
        KeyUp(Pressed[I]);
      Pressed[I].Code := 0;
    end;
end;

function LeftDirection: Integer;
var
  X, Y, Angle: Double;
begin
  X := AxisNorm(0);
  Y := AxisNorm(1);
  if Hypot(X, Y) < ChordThreshold then
    Exit(DIR_CENTER);
  Angle := RadToDeg(ArcTan2(-Y, X));      { 0 = east, 90 = north }
  Result := Round(Angle / 45);
  if Result < 0 then
    Inc(Result, 8);
  Result := Result mod 8;
end;

procedure HandleButton(Code: Word; Value: LongInt);
var
  I, D: Integer;
  Tok: TKeyTok;
begin
  I := -1;
  for D := 0 to BUTTON_COUNT - 1 do
    if ButtonCodes[D] = Code then
      I := D;
  if (I < 0) or (Value = 2) then
    Exit;
  Held[I] := Value = 1;

  if (Value = 1) and Held[ToggleA] and Held[ToggleB] then
  begin
    ReleaseAll;
    Active := not Active;
    Grab(Active);
    UpdateLed;
    Log('mapping ' + BoolToStr(Active, 'on', 'off (raw gamepad)'));
    Exit;
  end;
  if not Active then
    Exit;

  if Value = 0 then
  begin
    if Pressed[I].Code <> 0 then
    begin
      if Pressed[I].Code >= BTN_LEFT then
      begin
        Emit(MouseFd, EV_KEY, Pressed[I].Code, 0);
        Syn(MouseFd);
      end
      else
        KeyUp(Pressed[I]);
      Pressed[I].Code := 0;
    end;
    Exit;
  end;

  Tok.Shift := False;
  Tok.Code := 0;
  case Act[I].Kind of
    akKey:
      Tok.Code := Act[I].Code;
    akMouse:
      begin
        Emit(MouseFd, EV_KEY, Act[I].Code, 1);
        Syn(MouseFd);
        Pressed[I].Code := Act[I].Code;
        Pressed[I].Shift := False;
        Exit;
      end;
    akLayer:
      begin
        Layer := (Layer + 1) mod Length(Layers);
        UpdateLed;
        Log('layer ' + Layers[Layer].Name);
        Exit;
      end;
    akNone:
      if I < CHORD_BUTTONS then
      begin
        D := LeftDirection;
        Tok := Layers[Layer].Tok[D, I];
        Log(Format('chord %s+%s -> key %d%s',
          [DirNames[D], ButtonNames[I], Tok.Code, BoolToStr(Tok.Shift, ' +shift', '')]));
      end;
  end;
  if Tok.Code <> 0 then
  begin
    KeyDown(Tok);
    Pressed[I] := Tok;
  end;
end;

function MouseDeflected: Boolean;
begin
  Result := Hypot(AxisNorm(2), AxisNorm(3)) >= MouseDeadzone;
end;

procedure MoveMouse;
var
  X, Y, Mag, F: Double;
  DX, DY: Integer;
begin
  X := AxisNorm(2);
  Y := AxisNorm(3);
  Mag := Hypot(X, Y);
  if Mag < MouseDeadzone then
    Exit;
  F := Power((Min(Mag, 1) - MouseDeadzone) / (1 - MouseDeadzone), MouseAccel) * MouseSpeed;
  AccX := AccX + X / Mag * F;
  AccY := AccY + Y / Mag * F;
  DX := Trunc(AccX);
  DY := Trunc(AccY);
  AccX := AccX - DX;
  AccY := AccY - DY;
  if (DX = 0) and (DY = 0) then
    Exit;
  if DX <> 0 then
    Emit(MouseFd, EV_REL, REL_X, DX);
  if DY <> 0 then
    Emit(MouseFd, EV_REL, REL_Y, DY);
  Syn(MouseFd);
end;

procedure HandleAbs(Code: Word; Value: LongInt);
begin
  case Code of
    ABS_X: Axes[0].Value := Value;
    ABS_Y: Axes[1].Value := Value;
    ABS_RX: Axes[2].Value := Value;
    ABS_RY: Axes[3].Value := Value;
  end;
end;

{ ---------- main loop ---------- }

procedure OnSignal(Sig: cint); cdecl;
begin
  Terminated := True;
end;

function ReadEvents(Fd: cint; FromGamepad: Boolean): Boolean;
var
  Buf: array[0..63] of TInputEvent;
  N, I: TSsize;
begin
  N := FpRead(Fd, Buf, SizeOf(Buf));
  if N < 0 then
    Exit(fpgeterrno in [ESysEAGAIN, ESysEINTR]);
  for I := 0 to N div SizeOf(TInputEvent) - 1 do
    if FromGamepad and (Buf[I].Typ = EV_KEY) then
      HandleButton(Buf[I].Code, Buf[I].Value)
    else if not FromGamepad and (Buf[I].Typ = EV_ABS) then
      HandleAbs(Buf[I].Code, Buf[I].Value);
  Result := True;
end;

var
  ConfigFile: string;
  Fds: array[0..1] of pollfd;
  Timeout, I: Integer;
  LastMove, Now: QWord;
  Calibrate: Boolean;

begin
  ConfigFile := '/etc/rgpad.conf';
  I := 1;
  while I <= ParamCount do
  begin
    if ParamStr(I) = '-v' then
      Verbose := True
    else if (ParamStr(I) = '-c') and (I < ParamCount) then
    begin
      Inc(I);
      ConfigFile := ParamStr(I);
    end
    else
      Die('usage: rgpad [-c config] [-v]');
    Inc(I);
  end;

  LoadConfig(ConfigFile);
  SetupMapping;

  repeat
    GamepadFd := FindDevice(CfgStr('devices', 'gamepad', 'gpio-keys-gamepad'));
    JoystickFd := FindDevice(CfgStr('devices', 'joystick', 'adc-joystick'));
    if (GamepadFd >= 0) and (JoystickFd >= 0) then
      Break;
    if GamepadFd >= 0 then FpClose(GamepadFd);
    if JoystickFd >= 0 then FpClose(JoystickFd);
    Log('waiting for input devices...');
    Sleep(1000);
  until False;

  Calibrate := CfgBool('general', 'calibrate_on_start', True);
  InitAxis(0, ABS_X, Calibrate);
  InitAxis(1, ABS_Y, Calibrate);
  InitAxis(2, ABS_RX, Calibrate);
  InitAxis(3, ABS_RY, Calibrate);

  KbdFd := CreateUInput('rgpad keyboard', False);
  MouseFd := CreateUInput('rgpad mouse', True);

  FpSignal(SIGTERM, SignalHandler(@OnSignal));
  FpSignal(SIGINT, SignalHandler(@OnSignal));

  Active := True;
  Grab(True);
  UpdateLed;
  Log(Format('rgpad: %d layers, mapping on', [Length(Layers)]));

  Fds[0].fd := GamepadFd;
  Fds[0].events := POLLIN;
  Fds[1].fd := JoystickFd;
  Fds[1].events := POLLIN;
  LastMove := GetTickCount64;

  while not Terminated do
  begin
    if Active and MouseDeflected then
      Timeout := 1000 div MouseRate
    else
      Timeout := -1;
    if FpPoll(@Fds[0], 2, Timeout) < 0 then
      if fpgeterrno <> ESysEINTR then
        Die('poll failed');
    if (Fds[0].revents and (POLLERR or POLLHUP)) <> 0 then
      Die('gamepad device lost');
    if (Fds[1].revents and (POLLERR or POLLHUP)) <> 0 then
      Die('joystick device lost');
    if ((Fds[0].revents and POLLIN) <> 0) and not ReadEvents(GamepadFd, True) then
      Die('gamepad read failed');
    if ((Fds[1].revents and POLLIN) <> 0) and not ReadEvents(JoystickFd, False) then
      Die('joystick read failed');
    Now := GetTickCount64;
    if Active and (Now - LastMove >= QWord(1000 div MouseRate)) then
    begin
      MoveMouse;
      LastMove := Now;
    end;
  end;

  ReleaseAll;
  Grab(False);
  if LedName <> '' then
  begin
    WriteSys('/sys/class/leds/' + LedName + '/trigger', 'none');
    WriteSys('/sys/class/leds/' + LedName + '/brightness', '0');
  end;
  FpIOCtl(KbdFd, UI_DEV_DESTROY, nil);
  FpIOCtl(MouseFd, UI_DEV_DESTROY, nil);
end.
