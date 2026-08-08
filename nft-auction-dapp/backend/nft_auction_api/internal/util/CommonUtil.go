package util

import (
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
)

/**
 * @Description: 将十六进制地址字符串转换为 common.Address 类型
 * @param addr: 16进制地址字符串
 * @return: common.Address
 */
func Hex2Address(addr string) (common.Address, error) {
	if !common.IsHexAddress(addr) {
		return common.Address{}, fmt.Errorf("invalid address: %s", addr)
	}
	return common.HexToAddress(addr), nil
}

/**
 * @Description: 将字符串转换为 big.Int 类型
 * @param value: 数字字符串
 * @return: *big.Int, error
 */
func GetBigInt(value string, base int) (*big.Int, error) {
	number, ok := new(big.Int).SetString(value, base)
	if !ok {
		return nil, fmt.Errorf("invalid number: %s", value)
	}
	return number, nil
}

/**
 * @Description: 将字符串转换为 big.Int 类型
 * @param value: 数字字符串
 * @return: *big.Int, error
 * @Description: 将字符串转换为 big.Int 类型，确保非负整数
 */
func GetUbigInt(value string, base int) (*big.Int, error) {
	number, err := GetBigInt(value, base)
	if err != nil {
		return nil, err
	}
	if number.Sign() < 0 {
		return nil, fmt.Errorf("number must be non-negative")
	}
	return number, nil
}
