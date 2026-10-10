/* SPDX-License-Identifier: GPL-3.0-or-later
   Copyright (C) 2026 Shen Min

   nc-amp 2.0.0+ links the audio engine straight into nc-amp.exe, whose start-up code is
   Free Pascal's, not MinGW's: no MinGW CRT initialisation runs. The engine only uses the
   C runtime through msvcrt.dll (which initialises itself) and static MinGW helpers that
   need no start-up. The one CRT start-up service they ask for is atexit (mingwex's
   float formatting registers a critical-section cleanup); the process exits fine without
   it, so registering is a no-op here. */
int atexit(void (*fn)(void))
{
    (void)fn;
    return 0;
}

/* MinGW's math functions report domain / range errors here (errno is set by the caller).
   In MinGW's start-up library this only forwards to a user _matherr hook registered at
   start-up, and none is registered in nc-amp: nothing to do. */
void __mingw_raise_matherr(int type, const char *name, double arg1, double arg2, double result)
{
    (void)type; (void)name; (void)arg1; (void)arg2; (void)result;
}
