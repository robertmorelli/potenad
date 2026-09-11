# Latency measurements

Run the optimized native benchmark with:

    swift build -c release --scratch-path .build-performance -Xswiftc -DPERFORMANCE
    .build-performance/release/PoteNad --benchmark

before.txt and after.txt are local measurements from the same machine. Settings measurements include BOTH opening and closing, with Auto Layout flushed after each. Windows are not presented; measurements exclude WindowServer/display presentation. First-use costs are shown separately. Small timing differences are noise, not evidence of improvement.

Settings controls are now constructed once with each document window and retained. This moves their remaining construction cost to window creation; font lists and zoom choices are populated when their menus are used. The measured first Settings cycle dropped from 175 to 24 ms for the first empty window, and 83 to 9 ms for a subsequent 10,000-line window. Repeated cycles dropped from 79–88 to 4–5 ms.

UTF-8 serialization of 2.1 MB dropped from about 26 to 7.4 ms by avoiding newline replacements when no CR is present. Typing and zoom are approximately unchanged. These measurements do not establish a universal latency bound.
