#include <stdlib.h>

void* (*wfcMallocPtr)(void* context, size_t size) = 0;
void (*wfcFreePtr)(void* context, void* ptr) = 0;

float (*wfcRandPtr)(void *context) = 0;

#define WFC_MALLOC(ctx, sz) wfcMallocPtr(ctx, sz)
#define WFC_FREE(ctx, sz) wfcFreePtr(ctx, sz)
#define WFC_RAND(ctx) wfcRandPtr(ctx)

#define WFC_IMPLEMENTATION
#include "wfc.h"
