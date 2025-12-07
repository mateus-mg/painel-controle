# 🎛️ Painel de Controle - Gerenciador de Servidor

Script bash para gerenciar HD externo e containers Docker em servidor caseiro.



```bash
# Copiar script para local acessível
sudo cp painel.sh /usr/local/bin/painel

# Dar permissão de execução
sudo chmod +x /usr/local/bin/painel

# Testar
painel status
```

## 📋 Uso Rápido

### Inicialização do Servidor
```bash
painel mount        # Montar HD externo
painel start        # Iniciar todos os containers
painel keepalive    # Manter sistema ativo (Ctrl+C para sair)
```

### Desligamento do Servidor
```bash
painel stop         # Parar containers
painel unmount      # Desmontar HD
```

### Gerenciar Serviços Específicos
```bash
painel services            # Listar serviços disponíveis
painel start jellyfin      # Iniciar apenas Jellyfin
painel stop qbittorrent    # Parar apenas qBittorrent
painel restart plex        # Reiniciar apenas Plex
painel logs prowlarr -f    # Ver logs do Prowlarr em tempo real
```

## 📚 Comandos

### Gerenciamento de HD
| Comando | Descrição |
|---------|-----------|
| `painel mount` | Monta o HD externo |
| `painel unmount` | Desmonta o HD (para containers primeiro) |
| `painel check` | Mostra montagens ativas |
| `painel fix` | Corrige ponto de montagem |
| `painel force-mount` | Força remontagem completa |

### Gerenciamento Docker
| Comando | Descrição |
|---------|-----------|
| `painel start [servico]` | Inicia containers (todos ou específico) |
| `painel stop [servico]` | Para containers (todos ou específico) |
| `painel restart [servico]` | Reinicia containers (todos ou específico) |
| `painel ps` | Lista containers em execução |
| `painel logs <servico> [-f]` | Mostra logs de um serviço (use -f para follow) |
| `painel stats [servico]` | Mostra uso de CPU/memória em tempo real |
| `painel health` | Verifica saúde de todos os containers |

### Manutenção Docker
| Comando | Descrição |
|---------|-----------|
| `painel services` | Lista todos os serviços disponíveis |
| `painel pull` | Baixa imagens atualizadas |
| `painel rebuild [servico]` | Rebuild de containers |
| `painel update` | Atualização completa (pull + down + up) |
| `painel networks` | Lista redes Docker |
| `painel volumes` | Lista volumes Docker |
| `painel prune` | Remove recursos não utilizados |

### Monitoramento
| Comando | Descrição |
|---------|-----------|
| `painel status` | Status completo do sistema |
| `painel keepalive` | Modo monitoramento contínuo |
| `painel diagnose` | Diagnóstico detalhado |

## ⚙️ Configuração

Edite as variáveis no início do script:
```bash
HD_MOUNT_POINT="/media/mateus/Servidor"
DOCKER_COMPOSE_DIR="/home/mateus"
HD_DEVICE="/dev/sdb1"
```

## 🔋 Modo Keepalive

Mantém o HD ativo e monitora os containers:

```bash
painel keepalive
```

- Verifica HD a cada 30 segundos
- Remonta automaticamente se desconectar
- Reinicia containers que pararam
- **Ctrl+C para parar**

## 🐛 Solução de Problemas

### HD não monta
```bash
painel fix           # Corrigir ponto de montagem
painel force-mount   # Forçar montagem
lsblk                # Verificar dispositivo
```

### Containers não iniciam
```bash
painel status                    # Verificar sistema
painel logs <nome-do-servico>    # Ver logs
painel diagnose                  # Diagnóstico completo
```

## 📝 Logs

Logs salvos em `~/.painel.log`:

```bash
tail -20 ~/.painel.log    # Ver logs recentes
tail -f ~/.painel.log     # Acompanhar em tempo real
```
