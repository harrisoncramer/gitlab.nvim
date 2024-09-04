package app

func Contains[T comparable](elems []T, v T) int {
	for i, s := range elems {
		if v == s {
			return i
		}
	}
	return -1
}
