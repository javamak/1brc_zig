# 1 Billion Row Challenge - Zig Implementation

## Zig version: 0.15.2

## Build

To build the project with `ReleaseFast` optimizations:


```sh
zig build --release=fast
```

## Run

```sh
time ./zig-out/bin/1brc_zig
```

### Test machine config
Processor: i7 13700K <br>
RAM: DDR5 32 GB

### Execution time  in processor as below

real    0m2.161s<br>
user    0m45.055s<br>
sys     0m0.683s


### Execution time after using integers for storing and calculating the weather data and using std collections.

real    0m2.161s<br>
user    0m45.055s<br>
sys     0m0.683s

## Testing

The `test.sh` script builds the project in ReleaseFast mode and runs it against a test input file (`test-in.txt`), comparing the output to the expected result (`test-out.txt`).

To run the test:

```sh
./test.sh
```
