package main

import (
	"fmt"
	"os"
)

func dirExists(path string) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return fmt.Errorf("directory %s does not exist", path)
	}
	return nil
}
