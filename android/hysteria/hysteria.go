// Package hysteria provides a gomobile-compatible Hysteria client for Android.
package hysteria

import (
	"context"
	"fmt"
	"net"
	"os"
	"sync"
	"time"

	hycore "github.com/apernet/hysteria/core/v2/client"
)

// HysteriaClient is the main client wrapper exposed via gomobile bind.
type HysteriaClient struct {
	mu       sync.Mutex
	client   hycore.Client
	cancel   context.CancelFunc
	tunFd    *os.File
	started  bool
}

// NewHysteriaClient creates a new Hysteria client instance.
func NewHysteriaClient() *HysteriaClient {
	return &HysteriaClient{}
}

// Start connects to the Hysteria server and starts tunneling.
// serverAddr: host:port of the Hysteria server
// authString: authentication string (password or base64)
// tunFd: file descriptor of the Android TUN interface
// obfsPassword: optional obfuscation password (empty if none)
func (c *HysteriaClient) Start(serverAddr, authString string, tunFd int, obfsPassword string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.started {
		return fmt.Errorf("already started")
	}

	ctx, cancel := context.WithCancel(context.Background())
	c.cancel = cancel

	// Open TUN fd
	c.tunFd = os.NewFile(uintptr(tunFd), "tun")
	if c.tunFd == nil {
		cancel()
		return fmt.Errorf("invalid TUN fd %d", tunFd)
	}

	// Configure Hysteria client
	config := &hycore.ClientConfig{
		ServerAddr:   serverAddr,
		AuthString:   authString,
		ObfsPassword: obfsPassword,
		QUICConfig: hycore.QUICConfig{
			MaxIdleTimeout: 30 * time.Second,
			KeepAlivePeriod: 10 * time.Second,
		},
	}

	client, err := hycore.NewClient(ctx, config)
	if err != nil {
		cancel()
		return fmt.Errorf("failed to create hysteria client: %w", err)
	}
	c.client = client
	c.started = true

	// Start TUN forwarding
	go c.forwardTUN(ctx)

	return nil
}

// Stop disconnects from the Hysteria server and cleans up.
func (c *HysteriaClient) Stop() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.started {
		return nil
	}

	c.cancel()
	if c.client != nil {
		c.client.Close()
	}
	if c.tunFd != nil {
		c.tunFd.Close()
	}
	c.started = false
	return nil
}

// IsRunning returns true if the client is currently connected.
func (c *HysteriaClient) IsRunning() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.started
}

// forwardTUN reads packets from TUN and writes them through the Hysteria tunnel.
func (c *HysteriaClient) forwardTUN(ctx context.Context) {
	buf := make([]byte, 1500) // MTU
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		// Read from TUN
		n, err := c.tunFd.Read(buf)
		if err != nil {
			return
		}

		// Parse the IP packet and forward through Hysteria
		// Hysteria client provides a TCP/UDP proxy API
		// For now, we use the client's dialer
		packet := buf[:n]
		go c.handlePacket(ctx, packet)
	}
}

// handlePacket parses and forwards a single IP packet through Hysteria.
func (c *HysteriaClient) handlePacket(ctx context.Context, packet []byte) {
	// Simple IP packet parsing (IPv4)
	if len(packet) < 20 {
		return
	}
	version := packet[0] >> 4
	if version != 4 {
		return
	}

	proto := packet[9]
	dstIP := net.IP(packet[16:20])
	dstPort := uint16(packet[20])<<8 | uint16(packet[21])

	addr := fmt.Sprintf("%s:%d", dstIP.String(), dstPort)

	switch proto {
	case 6: // TCP
		conn, err := c.client.DialTCP(ctx, addr)
		if err != nil {
			return
		}
		defer conn.Close()
		// Forward TCP payload
		payload := packet[40:] // Skip IPv4 + TCP header
		conn.Write(payload)

	case 17: // UDP
		conn, err := c.client.DialUDP(ctx, addr)
		if err != nil {
			return
		}
		defer conn.Close()
		payload := packet[28:] // Skip IPv4 + UDP header
		conn.Write(payload)
	}
}
