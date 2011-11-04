Paper
'''''

Writing real time code on the XCore XS1
=======================================

Introduction
------------

This note describes the philosophy behind writing real-time programs for
the XCore XS1 architecture, and how to use *timers* to write basic
real-time programs, *port-clocks* to write more accurate
real-time programs, *events* to design real-time tasks that can react to a
multitude of inputs, and *threads* and *channels* to write complex scalable
real-time programs.

We first discuss the basics of getting data in and out of the system. We
then present how to write simple real-time tasks, and the timing guarantees
that the XCore instruction set offers. This allows the development of both
approximate and precisely timed real-time I/O. We then show how to deal with
alternative inputs in a real-time environment, and move on to
multi-threaded multi-core designs that can be used to implement tasks with
multiple (collaborating) real-time components.

Getting data in and out
-----------------------

Before discussing timings, we show how to input and output data. Inputting
data is the process of sampling one or more pins, and latching their value
into a variable. It is written using the ``:>`` operator::

    inputPort :> data;

This samples data on the port ``inputPort`` and stores the resulting value
into the variable called ``data``. Outputting data is the process of driving
data on pins, and it is written using the ``<:`` operator:: 

    outputPort <: value;

Which outputs the ``value`` onto the pins specified by the port ``outputPort``.
The operators ``:>`` and ``<:`` are used for inputting and outputting data
to all kinds of resources, and they are easily
remembered by viewing them as an arrow pointing from the port to the
variable, or from the value to the port.

Single real-time task with single input
---------------------------------------

Each real-time task that needs to be executed should be implemented as a single
*thread*. A thread that executes on an XCore is architecturally guaranteed
to execute instructions in a predictable manner, enabling the programmer to
reason about the real-time properties of their program.

Timing of instructions
......................

If a thread on an XCore is ready to execute an instruction, then the XCore
shall execute this instruction within a *thread-cycle*. A thread-cycle is equivalent to
N clock cycles where N is the number of threads that is in use on the core.
If less than four threads are in use on a core, then N equals four.

Hence, a thread has a guaranteed minimum performance of one instruction per
thread-cycle, and a computation comprising K instructions has an easily
computed maximum execution time of K thread-cycles, or K times N clock cycles.

There are three exceptions to this model:

#. Division instructions (DIV, REM, etc), take up to 32 thread-cycles to
   execute.

#. Instructions that perform I/O cannot proceed until the I/O is ready to proceed.

#. Occasionally, a sequence of instructions will require an extra thread
   cycle in order to fetch the instruction. These sequences can be
   recognised statically, and the tools will automatically incorporate the
   extra cycle in the prediction of the worst-case execution time.

The maximum execution time can be used to guarantee that a program will
always meet all its real-time deadlines. A simple real-time task that
performs a computation on some inputted data and outputs the answer is
structured as follows::

    inputPort :> data;       // Input data
    result = function(data); // Perform computation
    outputPort <: result;    // Output result

Because the time taken for the computation is known, the programmer can
statically predict the maximum time between input (``:>``) and output (``<:``), and be
satisfied that the result is output in time. 

The computation has a strict limit on its execution time, but may execute
faster than that. Reasons that the code may execute faster include that one
of the other threads has yielded the processor (freeing up the pipeline for
other instructions), or the code may have been
ported to a part with a higher clock frequency.

In many programs, it is not a problem if I/O happens too early, because
some ready or handshake signals will block the actual transfer. But in other
cases, I/O that is too early is a problem. There are two methods that can be
employed to stop I/O that is too early: waiting for a timer, or using a
port-clock for the output. These methods have different uses as they have
different levels of precision.

Using a *timer* to time I/O
...........................

The easiest method to time an output is to wait for a timer after the
computation is performed::

    inputPort :> data;                       // Input data
    result = function(data);                 // Perform computation
    tmr when timerafter(outputTime) :> void; // Wait for the right time
    outputPort <: result;                    // Output result

The XCore processor has built-in timers that enable a thread to wait for a
specific time. While waiting the thread will not be doing anything,
enabling other threads to run faster, or the processor may enter a sleep
mode if no threads require attention.

Using this method, the output (``<:``) will be performed just after the time
stored in ``outputTime``. Typically ``outputTime`` will be computed based
on the time that data was input, for example::

    inputPort :> data;                       // Input data
    tmr :> inputTime;                        // Get time that input happened
    outputTime = inputTime + 537;            // Compute time for output
    result = function(data);                 // Perform computation
    tmr when timerafter(outputTime) :> void; // Wait for the right time
    outputPort <: result;                    // Output result

There will be a slight uncertainty as to the precise timing of the output
in this program. Because the instructions executed whilst performing the
output are subject to the same
limitations as before, they have a strict maximum execution time, but may
run faster. The time measurement and output operations typically comprises
only a few instructions instruction so the
uncertainty is typically limited to tens of nanoseconds, but this may exceed
application requirements.

Using an application-clock to time I/O precisely
................................................

The second method to avoid performing I/O too early is to synchronise
output of data to the *application-clock*. The application clock is the
clock signal between the XCore and the external hardware that governs
transfer of data. For high precision timings this clock signal can be used
to perform I/O on a specific clock edge of the clock-signal::

    inputPort :> data;                 // Input data
    result = function(data);           // Perform computation
    outputPort @ clockCount <: result; // Output result on specific edge

This method has much lower jitter, and guarantees that the signal will be
visible nanoseconds after the required clock edge. Typically, the
clockCount is either based on when the data was input, or it is related to
a previous output on ``outputPort``. If the timing is related to the input,
then if the same clock is used on input and output the following code
sequence demonstrates how to make timings precisely::

    inputPort :> data @ inputClocks;     // Input data, with clock count
    outputClocks = inputClocks + 233;    // Compute when output should occur
    result = function(data);             // Perform computation
    outputPort @ outputClocks <: result; // Output result on specific edge

If the timing is related to a previous output, then the code will just
maintain the output time, which is shown below::

    for(int i = 0; i < 10; i++) {
        outputClocks = outputClocks + 233;   // Compute output timing
        result = function(i);                // Perform computation
        outputPort @ outputClocks <: result; // Output on specific edge
    }

In both cases, the timing verification has to verify that the call to
``function()`` requires no more than 233 application clock cycles, taking
into account any possible skew between the application clock and the core
clock.


Summary
.......

Computations that do not involve I/O have a strict upper limit on their
execution time, but not a useful lower-bound (if for no other reason that
the code can be executed on a faster part). Timers or application clocks
should be used to make sure that I/O is performed at the time required.

Choosing from multiple inputs
-----------------------------

When multiple inputs are available to a real-time task, and any of them may
be ready to be processed, then one of them has to be chosen for processing. An
example is a serial input device which may at any time see a change in the
input line (signalling the arrival of data) or may at any time be requested
to post data to the higher level software. One cannot in advance state in
which order these events arrive, for they are physically asynchronous activities.

There are two ways to deal with those; by using *events* or by using
*interrupts*. Events are the most efficient method, but on occasions
interrupts can be simpler. Interrupts can also be used to port legacy code
that uses interrupts to an XCore.

Events
......

Events are the preferred method for selecting one of multiple possible
inputs. We first look at the event mechanism at assembly level, before
showing the high level syntax.

At assembly level, the event mechanism on the XCore architecture requires the
programmer to:

#. Set up an *event-vector* for all the resources from which data may be expected.

#. Set the *condition* on which to wait.

#. *Enable* events on which to wait.

#. Execute a *wait instruction*.

Usually, the first three steps are executed once to set up an *event-loop*.
Once set-up, the wait-instruction is executed to dispatch an event, and
after the event is handled another wait instruction can be executed to
dispatch the next event.

The first step sets the addresses of the instruction sequence that deals with each
of the possible event sources. Each event source has a sequence of
instructions that handles the event, and the memory address of the start of
the sequence is called the event-vector.

The second step defines any conditions
associated with inputs (eg, wait for a falling edge). Conditions are
optional. 

The third step
enables events to be individually enabled and disabled. This enables
*guards* to be implemented, where a guard can block specific events from
being visible.

The fourth step, the wait-instruction, dispatches a single event. Three
variants of the wait instruction are provided that wait unconditionally, or
that wait if a condition is true or false. The location of the wait
instruction is irrelevant; once waiting the processor will dispatch the
next event to one of the event-vectors set up in Step 1.

In assembly code, a typical sequence of instructions for two event sources
X and Y is::

  Init:
      SETV X, EventX
      SETV Y, EventY
      EEU X
      EEU Y
      WAITEU

  EventX:
      INPUT from X
      deal with X
      WAITEU

  EventY:
      INPUT from Y
      deal with Y
      WAITEU

This sequence of code contains three WAITEU instructions. The normal entry
is through the initialisation sequence; on executing the WAITEU
instruction the thread pauses until an event on either X or Y. If, say,
input is available on Y, then the thread will execute code at ``EventY``
which ends with a WAITEU instruction, awaiting the next event.

The three code sequences that end with a WAITEU instruction all have a
guaranteed maximum time. If we calculate these times as tI, tX, and tY
thread-cycles, then we can analyse the worst case timing sequences.

If the thread is waiting, and X and Y become ready simultaneously, then one
of the two is executed first, followed by the other one. This means that
the worst case time is tX + tY thread-cycles. This assumes
that X does not happen more often than once every tX thread-cycles, and Y
does not become ready more often than once every tY thread-cycles. The
first event handled on initialisation may be delayed by an extra time tI
thread-cycles.

With this event mechanism, events are handled synchronously with the code,
which means that events are only taken in known places in the code, when
the state of the registers, memory, and resources are known. Register
allocation can be performed across the various event handlers.

In a high level language, such as XC, these events can be expressed by
means of a select statement::

    while(1) {
        select {
         case X :> a:
             // deal with event from X
             break;
         case Y :> b:
             // deal with event from Y
             break;
         }
     }

Guards can be used to selectively disable cases, enabling the
programmer to, in a single ``select`` statement, capture conditions such as
*buffer is full* or *receiving*. Guards are formulated as boolean
expressions that are specified after the ``case`` keyword: ``case
guardCondition => ...``. A full example of a select with guards is shown in the
appendix.


Interrupts
..........

Instead of events, interrupts can be used to deal with multiple inputs.
This is the traditional method for dealing with multiple inputs. Interrupts
typically have a high worst case execution-time, because an interrupt routine
has to save and restore context, and can make only few assumptions about the
state of registers, memory, and resources.

On an XCore interrupts are
rarely used since events can perform the task that an interrupt would have
been used for in a more intuitive and faster manner. The occasions where
interrupts are used are typically used for either long term time-outs, or
for monitoring external signals that override other functions. Examples are
the time-out that a USB stack requires if no Start-Of-Frame has been
received for 3ms, or an external RESET input that requires monitoring from
all states.

Interrupts are enabled, at assembly level, by requesting a resource to
interrupt on readyness, and to set the vector to point to the interrupt
handler.

Using multiple threads
----------------------

A thread can implement a single real-time task, using one of the forms
described above. Usually, a single real-time task controls a single
real-time interface, and responds to one or more communication interfaces
that interact with other parts of the system.

Multiple threads can together implement a larger scale real-time problem that
involves multiple real-time tasks. As an example, consider an industrial
controller. This may involve an actuator, a sensor, and a network
interface. These can be seen as three real-time tasks, that
interact with each other. These can be implemented by three threads, that
communicate with each other.

On the XCore, thread communication is provided in the form of *channels*
over *links* and *switches*. That is, a thread can communicate with another
thread by sending data over a channel. Channels are lossless and are used
in a synchronised manner unless specified otherwise. When two threads require to
communicate data over a channel, one thread outputs data onto the channel,
and the other thread inputs data from the channel::

    someChannel :> dataFromChannel;

and::

    someChannel <: dataToChannel;

To the programmer, communication looks just like I/O, and is reasoned about
in a similar manner as I/O. Like I/O, communication with other threads may
have real-time requirements that the thread has to adhere to.
Communication with other threads may also block a thread, which may affect
real-time performance, just like communication with an I/O device may
block a thread.

Continuing the example above, the actuator thread, sensor thread, and
network-interface thread could, for example, communicate by means of two
channels, one between the sensor thread and the actuator thread, and one
between the network-interface and the actuator thread. The actuator is
controlled based on information retrieved from the sensor, and governed by
information received over the network interface.

Each of the three threads now has its own specific set of real-time
properties, and the designer can ensure that the implementation of each
thread meets the real-time requirements. When all threads meet their
real-time requirement, the system as a whole meets its real-time
requirements.

It is worth noting that using multiple threads to implement a multitude of
real-time tasks is a well-established design pattern. An alternative
implementation would use three processing units (eg, micro controllers)
each implementing one of the real-time tasks. This strategy
has been successfully used for decades.

Threads do not have to be used exclusively for real-time tasks. They can be
used to implement other tasks, for example computational tasks or
control-tasks. Whereas in the past a DSP would have been added to the
design to implement the numeric part of the algorithm, this task can be
folded into one or more XCore threads.

Appendix: Complete example code
-------------------------------

A complete example of a select with timers, I/O and guards is:

.. literalinclude:: app_example_code/src/uart.xc
  :start-after: //:: uartcode
  :end-before: //::


