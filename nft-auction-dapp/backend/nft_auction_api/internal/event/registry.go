package event

import (
	"fmt"
	"reflect"
	"sync"
)

// ListenerRegistry 全局 Listener 注册表
// 具体监听器的注册代码统一放在 internal/config/listener_register.go 中管理
type ListenerRegistry struct {
	mu sync.RWMutex
	// eventName -> listener type
	eventTypes map[string]reflect.Type
}

var (
	registry     *ListenerRegistry
	registryOnce sync.Once
)

// GlobalRegistry 获取全局 Listener 注册表
func GlobalRegistry() *ListenerRegistry {
	registryOnce.Do(func() {
		registry = &ListenerRegistry{
			eventTypes: make(map[string]reflect.Type),
		}
	})
	return registry
}

// RegisterMapping 注册事件名 → Listener 类型的映射
// eventName: 合约事件名，如 "AuctionCreated"
// typ: 监听器的 reflect.Type，如 reflect.TypeOf(AuctionCreatedListener{})
func (r *ListenerRegistry) RegisterMapping(eventName string, typ reflect.Type) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.eventTypes[eventName] = typ
}

// GetEventNames 返回所有已注册的事件名
func (r *ListenerRegistry) GetEventNames() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	names := make([]string, 0, len(r.eventTypes))
	for k := range r.eventTypes {
		names = append(names, k)
	}
	return names
}

// CreateListener 根据事件名创建 Listener 实例
func (r *ListenerRegistry) CreateListener(eventName string) (EventListener, error) {
	r.mu.RLock()
	typ, ok := r.eventTypes[eventName]
	r.mu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("no listener registered for event %q", eventName)
	}

	instance := reflect.New(typ).Elem().Addr().Interface()
	listener, ok := instance.(EventListener)
	if !ok {
		return nil, fmt.Errorf("type for event %q does not implement EventListener", eventName)
	}
	return listener, nil
}
