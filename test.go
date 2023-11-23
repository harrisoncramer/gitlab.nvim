package main

import "fmt"

// Define an interface with the method you want to mock.
type Orangeable interface {
	Orange()
}

// Banana struct and its method Orange.
type Banana struct{}

func (b *Banana) Orange() {
	fmt.Println("Hello")
}

// Apple struct now implements Orangeable.
type Apple struct {
	Banana Banana
}

func (a *Apple) Orange() {
	a.Banana.Orange()
}

// Modify myFunc to accept anything that satisfies the Orangeable interface.
func myFunc(o Orangeable) {
	o.Banana.Orange()
}
