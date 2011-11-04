//:: uartcode
#include <xs1.h>

#define MAX 10

void uartThread(in port inputPort, chanend byteChannel) {
    timer tmr;
    int inByte = 0, empty = 1, bitsReceived = 0;
    unsigned int byte = 0, bitValue;
    unsigned char byteArray[MAX];
    unsigned int rd = 0, wr = 0;
    unsigned int middleOfBit, bitTime = 100000000/115200;
    while(1) {
        select {
        case !inByte => inputPort when pinsneq(1) :> void:
            tmr :> middleOfBit;
            middleOfBit += bitTime + bitTime/2;
            inByte = 1;
            bitsReceived = 0;
            break;
        case inByte => tmr when timerafter(middleOfBit) :> void:
            inputPort :> bitValue;
            byte = byte >> 1;
            if (bitValue) {
                byte |= 0x80;
            }
            bitsReceived++;
            if (bitsReceived == 8) {
                inByte = 0;
                byteArray[wr++] = byte;
                if (wr >= MAX) wr = 0;
                empty = 0;
            } else {
                middleOfBit += bitTime;
            }
            break;
        case !empty => byteChannel :> unsigned char _:
            byteChannel <: byteArray[rd++];
            if (rd >= MAX) rd = 0;
            if (rd == wr) empty = 1;
            break;
        }
    }
}
//::

main() {}
