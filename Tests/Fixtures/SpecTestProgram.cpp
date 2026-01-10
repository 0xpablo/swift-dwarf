#include "SpecTestProgram.hpp"

int SpecTestProgramFoo::bar(int value) {
    return value + 1;
}

int specTestProgramFreeFunction(int value) {
    return value + 2;
}

int main() {
    SpecTestProgramFoo foo;
    return foo.bar(3) + specTestProgramFreeFunction(4);
}
