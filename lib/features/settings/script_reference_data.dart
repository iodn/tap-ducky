typedef ScriptReferenceEntry = ({String syntax, String description});

const scriptReference = <String, List<ScriptReferenceEntry>>{
  'Text and Comments': [
    (
      syntax: 'STRING text / STRINGLN text',
      description:
          'Type literal text into the focused window. STRINGLN adds Enter. '
          'Quotes are literal, and runtime variables are not interpolated. Match '
          'TapDucky\'s keyboard layout to the host layout.',
    ),
    (
      syntax: 'STRING ... END_STRING / STRINGLN ... END_STRINGLN',
      description:
          'Put the opener and closer on their own lines. STRING joins body '
          'lines without separators; STRINGLN inserts a newline between body '
          'lines and adds a final Enter for a nonempty block. Prefix a literal '
          'closing marker with a backslash to type it instead of ending the block.',
    ),
    (
      syntax: 'STRING_DELAY ms text / STRINGDELAY ms text',
      description:
          'Type one line with an additional per-character pause. The '
          'delay is an integer literal in milliseconds, not an expression.',
    ),
    (
      syntax: 'REM comment / REM_BLOCK ... END_REM',
      description:
          'Skip a line or a block. REMBLOCK also opens a block; use '
          'END_REM alone to close it. Use REM rather than # or inline comments.',
    ),
    (
      syntax: 'DEFINE label replacement',
      description:
          'Replace matching text on subsequent lines, including text '
          'inside STRING blocks. Labels are case-sensitive. Labels starting '
          'with # can match inside text; other labels must be separated by '
          'whitespace or line boundaries. Replacement is a single pass.',
    ),
  ],
  'Keyboard and Media': [
    (
      syntax: 'ENTER, TAB, SPACE, ESCAPE (ESC), BACKSPACE (BKSP), DELETE (DEL)',
      description:
          'Tap an editing key once. A single A-Z or 0-9 also works as a key tap.',
    ),
    (
      syntax:
          'UP (UPARROW), DOWN (DOWNARROW), LEFT (LEFTARROW), RIGHT (RIGHTARROW)',
      description: 'Tap an arrow key.',
    ),
    (
      syntax: 'HOME, END, PAGEUP, PAGEDOWN, INSERT (INS)',
      description:
          'Tap a navigation or editing key. The editor can warn on standalone INS.',
    ),
    (
      syntax: 'CAPSLOCK, NUMLOCK, SCROLLLOCK, F1 through F24',
      description:
          'Tap a lock or function key. The host decides how to handle it.',
    ),
    (
      syntax: 'MENU (APP), PAUSE (BREAK), PRINTSCREEN (PRINTSCRN, PRTSCN)',
      description:
          'Tap a system key. PRINTSCRN works as a standalone command; '
          'use PRINTSCREEN or PRTSCN in a chord or HOLD.',
    ),
    (
      syntax: 'NUMPAD_0 through NUMPAD_9 / KP0 through KP9',
      description:
          'Tap a keypad digit. The underscore is optional in NUMPAD names.',
    ),
    (
      syntax:
          'NUMPAD_PLUS (KPPLUS), NUMPAD_MINUS (KPMINUS), NUMPAD_MULTIPLY (KPASTERISK), '
          'NUMPAD_DIVIDE (KPSLASH), NUMPAD_ENTER (KPENTER), NUMPAD_PERIOD (KPDOT)',
      description: 'Tap a keypad operator, Enter, or decimal key.',
    ),
    (
      syntax: 'CTRL A / CTRL-A',
      description:
          'Tap one key with modifiers; for example, select all in a text '
          'editor. Use spaces or hyphens between chord tokens. A modifier by '
          'itself is not a tap; use HOLD and RELEASE.',
    ),
    (
      syntax: 'CTRL (CONTROL), SHIFT, ALT, GUI (WINDOWS, COMMAND, WIN)',
      description:
          'Left-side modifiers. OPTION is recognized as a command token '
          'but does not map to a modifier at runtime; use ALT.',
    ),
    (
      syntax: 'RCTRL (RCONTROL), RSHIFT, RALT, RGUI (RWINDOWS, RCOMMAND)',
      description:
          'Right-side modifiers. Some runtime modifier aliases may be '
          'flagged by the editor.',
    ),
    (
      syntax: 'HOLD keys / KEY_DOWN keys (KEYDOWN)',
      description:
          'Keep keys or modifiers pressed. Separate tokens with spaces '
          'or +. The keyboard report has six non-modifier key slots.',
    ),
    (
      syntax: 'RELEASE keys / KEY_UP keys (KEYUP)',
      description:
          'Release specific held keys or modifiers. This does not clear '
          'the separate INJECT_MOD modifier mask.',
    ),
    (
      syntax: 'INJECT_MOD modifiers / INJECTMOD modifiers',
      description:
          'Replace the persistent modifier mask for keyboard output. '
          'Separate modifiers with spaces or +. Clear it with no argument, '
          'CLEAR, NONE, OFF, or 0.',
    ),
    (
      syntax: 'INJECT_VAR expression / INJECTVAR expression',
      description:
          'Tap a packed keyboard scancode. The low byte is the key code '
          '(0x04 to 0xDF); the high byte is the modifier mask. An ASCII value '
          'is not a keyboard scancode.',
    ),
    (
      syntax:
          'MEDIA_PLAYPAUSE (PLAYPAUSE), MEDIA_STOP (STOPCD), MEDIA_PREV (PREVIOUSSONG), '
          'MEDIA_NEXT (NEXTSONG)',
      description: 'Send a playback control on a media-capable HID interface.',
    ),
    (
      syntax:
          'MEDIA_VOLUMEUP (VOLUMEUP), MEDIA_VOLUMEDOWN (VOLUMEDOWN), MEDIA_MUTE (MUTE)',
      description:
          'Send a volume control. Media commands may have no effect when '
          'the media interface is unavailable.',
    ),
  ],
  'Pointer': [
    (
      syntax: 'MOUSE CLICK button [count]',
      description:
          'Click LEFT, RIGHT, or MIDDLE. POINTER is an alias for MOUSE '
          'in every form. Pointer commands require a mouse HID interface.',
    ),
    (
      syntax: 'MOUSE MOVE dx dy [count] / MOUSE SCROLL UP|DOWN [count]',
      description:
          'Move by signed relative deltas or scroll by one wheel report '
          'per count. Movement is limited to -127 through 127 per axis per report.',
    ),
    (
      syntax:
          'MOUSE HOLD button [dx [dy [count]]] / MOUSE DRAG button [dx [dy [count]]]',
      description:
          'Press a button and optionally move. HOLD leaves it down and '
          'there is no MOUSE RELEASE command. DRAG restores the prior button '
          'state, so use it for a self-contained drag. Deltas default to zero. '
          'Pointer counts are integer literals, default to one, and have a minimum of one.',
    ),
  ],
  'Timing and Readiness': [
    (
      syntax: 'DELAY expression / DEFAULT_DELAY expression (DEFAULTDELAY)',
      description:
          'Wait once, or set a pause after subsequent executed commands. '
          'Values are milliseconds; DEFAULT_DELAY 0 disables the default pause. '
          'Scaled script delays are capped at five minutes.',
    ),
    (
      syntax: 'SLEEP_UNTIL ms|epochMs|HH:MM[:SS] / SLEEPUNTIL',
      description:
          'Fewer than 10 digits mean a relative delay in milliseconds. '
          'At least 10 digits mean Unix epoch milliseconds, not seconds. A '
          'clock time uses the Android device\'s local time and rolls over to '
          'tomorrow if already reached. Only relative waits use the delay multiplier.',
    ),
    (
      syntax: 'WAIT_FOR target [timeoutMs] / WAITFOR target [timeoutMs]',
      description:
          'Wait for HOST_CONNECTED (HOST), UDC_CONFIGURED (UDC), '
          'KEYBOARD_READY (KBD_READY), MOUSE_READY, or SESSION_ARMED (ACTIVE). '
          'The integer timeout defaults to 15000 ms. A timeout raises a runtime error.',
    ),
  ],
  'Control Flow and Functions': [
    (
      syntax:
          'IF expression [THEN] ... ELSE IF expression [THEN] ... ELSE ... END_IF',
      description:
          'Run only the first matching branch. ELSE IF and ELSE are '
          'optional. Write ELSE IF as two words even though the editor recognizes '
          'ELSE_IF. ENDIF is also accepted.',
    ),
    (
      syntax: 'WHILE expression [DO] ... END_WHILE / ENDWHILE',
      description:
          'Re-evaluate the condition before each iteration. Zero is false.',
    ),
    (
      syntax: 'TRY ... CATCH ... END_TRY / ENDTRY',
      description:
          'Handle runtime failures, not parse errors, cancellation, '
          'failed Continue prompts, RETURN, or STOP_PAYLOAD. Without CATCH, '
          'the runtime error propagates.',
    ),
    (
      syntax: 'REPEAT count',
      description:
          'Add copies of the previous parsed command, not a block. '
          'Use an integer from 1 to 20000; the sum of REPEAT counts is capped '
          'at 20000 per script. Expansion occurs outside function bodies.',
    ),
    (
      syntax: r'FUNCTION name($arg1, $arg2) ... END_FUNCTION / ENDFUNCTION',
      description:
          'Declare a function. Omit parentheses for a definition with '
          'no parameters, or use name(). Parameter names may omit the dollar '
          'prefix in the header; use it in the body. Reserved variables cannot '
          'be parameters. Function and variable names are case-sensitive.',
    ),
    (
      syntax: 'name(expression, expression) / name()',
      description:
          'Call a function on its own line with comma-separated numeric '
          'arguments. Missing arguments default to zero; extra arguments are '
          'ignored. Parameters are local; other writes update a matching active '
          'parameter or the script-wide variable. Call depth is capped at 64.',
    ),
    (
      syntax: 'RETURN [expression]',
      description:
          r'End the function with a result in 0 to 65535, also stored in $?. '
          'A bare RETURN or reaching the end of a function returns zero. '
          'Only calls written without arguments can appear inside expressions.',
    ),
    (
      syntax: 'STOP_PAYLOAD / STOPPAYLOAD',
      description:
          'End the entire script, including from a function or button callback.',
    ),
  ],
  'Variables and Expressions': [
    (
      syntax:
          r'VAR $name [= expression] / VAR $name expression / $name = expression',
      description:
          'Declare or assign a numeric variable. A declaration without a '
          'value starts at zero; user values and function arguments are clamped '
          'to 0 through 65535. Names use letters, digits, and underscores after '
          'the dollar sign. Unknown ordinary variables read as zero; unknown '
          'internal names starting with a dollar sign and underscore can fail.',
    ),
    (
      syntax: r'$?',
      description:
          'Writable status slot, but most commands reset it to zero. '
          'Read a function result before the next command overwrites it.',
    ),
    (
      syntax: '42, 0x2A, TRUE, FALSE, (expression)',
      description:
          'Use decimal or hexadecimal integers, booleans (1 or 0), and '
          'parentheses. Expressions are numeric, not strings or floating-point values.',
    ),
    (
      syntax: '+ - * / % ^',
      description:
          'Integer arithmetic. Division and remainder by zero raise an '
          'error. ^ is right-associative exponentiation, not XOR. Unary signs '
          'bind before ^. Basic arithmetic such as addition and multiplication '
          'saturates at signed 32-bit bounds before storage clamping.',
    ),
    (
      syntax: '<< >> & |',
      description:
          'Unsigned 16-bit shifts, bitwise AND, and bitwise OR. All '
          'return 16-bit results; shift counts outside 0 to 15 produce zero.',
    ),
    (
      syntax: '= == != < <= > >= ! && || AND OR',
      description:
          'Compare or combine conditions. In an expression, = aliases ==. '
          'Nonzero is true; comparisons and logical operations return 0 or 1. '
          'AND and OR evaluate both sides, even when the left side decides the result.',
    ),
  ],
  'Random Values': [
    (
      syntax:
          'RANDOM_LOWERCASE_LETTER, RANDOM_UPPERCASE_LETTER, RANDOM_LETTER, '
          'RANDOM_NUMBER, RANDOM_SPECIAL, RANDOM_CHAR [count]',
      description:
          'Type random lowercase letters, uppercase letters, mixed letters, '
          'digits, punctuation, or a mix respectively. Each command accepts an '
          'optional integer count (default and minimum 1). Underscores are optional.',
    ),
    (
      syntax: r'$_RANDOM_MIN, $_RANDOM_MAX',
      description:
          'Writable inclusive bounds for RANDOM_INT, each 0 to 65535. '
          'They start at 0 and 9. The minimum must not exceed the maximum when read.',
    ),
    (
      syntax: r'$_RANDOM_INT, $_RANDOM_UINT16, $_RANDOM_SEED',
      description:
          'Read-only. Each read of RANDOM_INT draws within the configured '
          'bounds; RANDOM_UINT16 always draws from 0 through 65535. RANDOM_SEED '
          'reports the variable generator\'s seed and cannot be set by a script.',
    ),
    (
      syntax:
          r'$_RANDOM_ASCII_LOWER_LETTER, $_RANDOM_ASCII_UPPER_LETTER, '
          r'$_RANDOM_ASCII_LETTER, $_RANDOM_ASCII_NUMBER',
      description:
          'Read-only random ASCII codes for lowercase, uppercase, mixed '
          'letters, or digits respectively. These are not packed keyboard codes.',
    ),
    (
      syntax:
          r'$_RANDOM_LOWER_LETTER_KEYCODE, $_RANDOM_UPPER_LETTER_KEYCODE, '
          r'$_RANDOM_LETTER_KEYCODE, $_RANDOM_NUMBER_KEYCODE, '
          r'$_RANDOM_SPECIAL_KEYCODE, $_RANDOM_CHAR_KEYCODE',
      description:
          'Read-only. Draw packed key codes from lowercase, uppercase, '
          'mixed letters, digits, punctuation, or all those sets. Only characters '
          'that map to a single keystroke in the selected layout are eligible. '
          'A read fails if its set has no eligible keys. Use with INJECT_VAR.',
    ),
  ],
  'Buttons and Indicators': [
    (
      syntax: 'WAIT_FOR_BUTTON_PRESS / WAITFORBUTTONPRESS',
      description:
          'Pause for Continue in an app-started run with an active app '
          'connection. It is not a host key or physical Rubber Ducky button.',
    ),
    (
      syntax: 'BUTTON_DEF ... END_BUTTON / BUTTONDEF ... ENDBUTTON',
      description:
          'Register a callback for the in-app script button as execution '
          'reaches the definition. The callback runs at an execution checkpoint. '
          'Do not nest button definitions or cross other block boundaries.',
    ),
    (
      syntax: 'ENABLE_BUTTON / DISABLE_BUTTON (ENABLEBUTTON / DISABLEBUTTON)',
      description:
          'Enable or disable the in-app script button for the current run.',
    ),
    (
      syntax:
          r'$_BUTTON_ENABLED, $_BUTTON_USER_DEFINED, $_BUTTON_PUSH_RECEIVED',
      description:
          'Writable flags (zero is off, nonzero is on). They control the '
          'script button, enable a previously defined callback, and record or '
          'clear the press flag respectively. Setting the press flag does not '
          'trigger the callback.',
    ),
    (
      syntax: r'$_BUTTON_TIMEOUT',
      description:
          'Writable button cooldown in milliseconds (0 to 65535, default '
          '1000). It is not a deadline for pressing Continue.',
    ),
    (
      syntax: 'LED_OFF (LEDOFF), LED_R (LEDR), LED_G (LEDG)',
      description:
          'Set the in-app script indicator to off, red, or green. LED_OFF '
          'also clears both LED enable flags. No physical LED is controlled.',
    ),
    (
      syntax: r'$_INJECTING_LEDS_ENABLED, $_SYSTEM_LEDS_ENABLED',
      description:
          'Writable activity and system indicator flags. Both start '
          'enabled; zero disables and nonzero enables the corresponding app indicator.',
    ),
  ],
  'Host and USB Compatibility': [
    (
      syntax: 'DETECT_OS()',
      description:
          'Standalone command that waits up to 10 seconds for pending '
          'host detection. It does not return the OS as an expression or force '
          'a new detection. Read the OS variable afterward.',
    ),
    (
      syntax: r'$_OS',
      description:
          'Read-only host detection result. Use the uppercase symbolic '
          'constants UNKNOWN (0), WINDOWS (1), MACOS (2), LINUX (3), CHROMEOS (4), '
          'ANDROID (5), IOS (6). UNKNOWN can mean pending, unavailable, or '
          'disconnected. This reads the inferred OS, not the manual OS setting.',
    ),
    (
      syntax:
          'EXTENSION OS_DETECTION ... END_EXTENSION / EXTENSION OS_DETECT ... END_EXTENSION',
      description:
          'Recognize an imported OS-detection wrapper and skip its entire '
          'body. Other extension names are rejected. Use the exact marker spelling.',
    ),
    (
      syntax: r'$_CURRENT_VID, $_CURRENT_PID, $_CURRENT_ATTACKMODE',
      description:
          'Read-only observed USB state. VID and PID use Hak5-style '
          'byte-swapped values. Mode codes are OFF (0), HID (1), storage (2), '
          'or HID plus storage (3). Reads fail when the needed state cannot be verified.',
    ),
    (
      syntax: 'ATTACKMODE (ATTACK_MODE)',
      description:
          'Recognized for compatibility but does not change USB mode in '
          'this build. Do not rely on it to configure the USB session.',
    ),
    (
      syntax: 'Command spelling and validation',
      description:
          'Command keywords are case-insensitive. The runtime strips '
          'underscores from many command keywords; use the spellings shown here '
          'for the best editor compatibility. Validation and timing estimates '
          'are advisory and cannot confirm host support or runtime readiness.',
    ),
  ],
  'Unavailable Reserved Variables': [
    (
      syntax:
          r'$_STORAGE_LEDS_ENABLED, $_LED_CONTINUOUS_SHOW_STORAGE_ACTIVITY, '
          r'$_EXFIL_LEDS_ENABLED, $_LED_SHOW_CAPS, $_LED_SHOW_NUM, $_LED_SHOW_SCROLL, '
          r'$_LED_SHOW_STORAGE_ACTIVITY',
      description:
          'Unavailable hardware indicator variables. Neither reads nor writes are supported.',
    ),
    (
      syntax:
          r'$_CAPSLOCK_ON, $_NUMLOCK_ON, $_SCROLLLOCK_ON, $_SAVED_CAPSLOCK_ON, '
          r'$_SAVED_NUMLOCK_ON, $_SAVED_SCROLLLOCK_ON, $_RECEIVED_HOST_LOCK_LED_REPLY',
      description:
          'Unavailable host lock state and reply variables. Neither reads nor writes are supported.',
    ),
    (
      syntax:
          r'$_JITTER_ENABLED, $_JITTER_MAX, $_STORAGE_ACTIVITY_TIMEOUT, '
          r'$_EXFIL_MODE_ENABLED, $_HOST_CONFIGURATION_REQUEST_COUNT, '
          r'$_PAYLOAD_PARSE_SPEED, $_STORAGE_ACTIVE',
      description:
          'Unavailable hardware timing, storage, and USB counters or flags. '
          'Neither reads nor writes are supported.',
    ),
    (
      syntax: r'$_RANDOM_ASCII_SPECIAL, $_RANDOM_ASCII_CHAR',
      description:
          'Unavailable random ASCII variables. Neither reads nor writes are supported.',
    ),
  ],
  'Payload Parameters and Examples': [
    (
      syntax: r'{{NAME}} / ${NAME}',
      description:
          'Payload parameter placeholders are replaced as text before '
          'the Kotlin parser runs. Whitespace around the name is trimmed, keys '
          'are case-sensitive, and unmatched placeholders remain unchanged. '
          'Values are inserted as-is, without quoting or escaping. These are '
          'not runtime variables or function parameters.',
    ),
    (
      syntax: 'Parameter key, label, type, default, description, required',
      description:
          'Configure these fields on the payload. The key matches the '
          'placeholder and the label is shown when configuring a run. Text, '
          'Number, and URL are metadata; replacement always inserts a string.',
    ),
    (
      syntax:
          'REM Focus a blank text editor first\nSTRINGLN Notes\nSTRINGLN {{NOTE}}',
      description:
          'Use a payload parameter named NOTE with a plain text value '
          'such as Review draft. The configured value is typed as the second line.',
    ),
    (
      syntax: 'STRINGLN First line\nSTRING Second line\nHOME\nSHIFT END',
      description:
          'In a blank text editor, type two lines and move the caret to '
          'the start of the second line before selecting it with Shift+End.',
    ),
  ],
};
