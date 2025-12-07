#!/bin/bash

# =============================================================================
# PAINEL DE CONTROLE - VERSÃO COMPLETA COM DOCKER E KEEPALIVE
# =============================================================================

# Configurações
HD_MOUNT_POINT="/media/mateus/Servidor"
DOCKER_COMPOSE_DIR="/home/mateus"
DOCKER_COMPOSE_FILE="$DOCKER_COMPOSE_DIR/docker-compose.yml"
LOG_FILE="$HOME/.painel.log"

# ✅ CONFIGURAÇÃO ESPECÍFICA DO SEU HD
HD_UUID="35feb867-8ee2-49a9-a1a5-719a67e3975a"
HD_LABEL="Servidor"
HD_TYPE="ext4"

# ✅ DETECTAR DISPOSITIVO AUTOMATICAMENTE PELO UUID
get_device_by_uuid() {
    # Busca o device pelo UUID (mais confiável)
    local device=$(blkid -U "$HD_UUID" 2>/dev/null)
    if [ -n "$device" ]; then
        echo "$device"
        return 0
    fi
    
    # Fallback: busca pelo LABEL
    device=$(blkid -L "$HD_LABEL" 2>/dev/null)
    if [ -n "$device" ]; then
        echo "$device"
        return 0
    fi
    
    return 1
}

# Tratamento de sinais para cleanup seguro
cleanup_on_exit() {
    echo ""
    echo "🛑 Sinal de interrupção recebido..."
    log_message "Keepalive interrompido pelo usuário"
    echo "✅ Keepalive finalizado com segurança"
    exit 0
}

trap cleanup_on_exit SIGINT SIGTERM

# Função de log com rotação automática
log_message() {
    local log_max_lines=1000
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    
    # Rotaciona log se necessário (mantém últimas 500 linhas)
    if [ -f "$LOG_FILE" ]; then
        local line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$line_count" -gt "$log_max_lines" ]; then
            tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null
            mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
        fi
    fi
}

# ✅ FUNÇÃO: Buscar serviços automaticamente do docker-compose.yml
get_docker_services() {
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo "❌ Arquivo docker-compose.yml não encontrado: $DOCKER_COMPOSE_FILE"
        return 1
    fi
    
    # Extrai os nomes dos serviços usando docker compose
    if command -v docker &> /dev/null; then
        cd "$DOCKER_COMPOSE_DIR" && docker compose config --services 2>/dev/null
        return $?
    else
        # Fallback: extrai manualmente do YAML
        grep -E '^  [a-zA-Z0-9_-]+:' "$DOCKER_COMPOSE_FILE" | sed 's/^  //' | sed 's/:$//'
    fi
}

# ✅ FUNÇÃO: Carregar serviços automaticamente
load_docker_services() {
    DOCKER_SERVICES=($(get_docker_services))
    
    if [ ${#DOCKER_SERVICES[@]} -eq 0 ]; then
        echo "⚠️  Nenhum serviço encontrado no docker-compose.yml"
        return 1
    fi
    
    return 0
}

# ✅ FUNÇÃO: Verificar ambiente Docker
check_docker_environment() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        return 1
    fi
    
    return 0
}

# ✅ FUNÇÃO: Limpar containers antigos/órfãos
clean_old_containers() {
    local service="$1"
    
    echo "🧹 Limpando containers antigos..."
    echo ""
    
    if ! check_docker_environment; then
        echo "⚠️  Docker não disponível"
        return 1
    fi
    
    cd "$DOCKER_COMPOSE_DIR" || return 1
    
    # Se um serviço específico foi informado
    if [ -n "$service" ]; then
        echo "🗑️  Removendo container antigo: $service"
        docker compose rm -f -s "$service" 2>/dev/null
    else
        echo "🗑️  Removendo todos os containers parados..."
        docker compose rm -f -s 2>/dev/null
    fi
    
    echo "✅ Limpeza concluída"
    log_message "Containers antigos removidos$([ -n "$service" ] && echo ": $service" || echo "")"
}

# ✅ FUNÇÃO: Parar containers Docker (agora aceita serviço específico)
stop_docker_services() {
    local service="$1"
    
    echo "🐳 Parando serviços Docker..."
    echo ""
    
    if ! check_docker_environment; then
        echo "⚠️  Docker não disponível"
        return 1
    fi
    
    cd "$DOCKER_COMPOSE_DIR" || return 1
    
    # Se um serviço específico foi informado
    if [ -n "$service" ]; then
        echo "⏹️  Parando serviço específico: $service"
        echo ""
        docker compose stop "$service" 2>&1
        log_message "Serviço parado: $service"
    else
        # Para todos os serviços
        if load_docker_services; then
            echo "🛑 Parando todos os serviços: ${DOCKER_SERVICES[*]}"
            echo ""
            for service_item in "${DOCKER_SERVICES[@]}"; do
                echo "⏹️  Parando: $service_item"
                docker compose stop "$service_item" 2>&1
                log_message "Serviço parado: $service_item"
            done
        else
            echo "🛑 Parando todos os containers..."
            docker compose stop 2>&1
            log_message "Todos os serviços parados"
        fi
    fi
    
    sleep 3
    echo ""
    echo "✅ Serviços Docker parados"
    echo ""
}

# ✅ FUNÇÃO: Iniciar containers Docker (agora aceita serviço específico e flag --clean)
start_docker_services() {
    service=""
    clean_mode=false
    no_deps=false
    
    # Parse de argumentos (aceita: service, --clean, --no-deps ou combinações)
    for arg in "$@"; do
        if [ "$arg" = "--clean" ]; then
            clean_mode=true
        elif [ "$arg" = "--no-deps" ]; then
            no_deps=true
        elif [ -n "$arg" ]; then
            service="$arg"
        fi
    done
    
    echo "🐳 Iniciando serviços Docker..."
    echo ""
    
    if ! check_docker_environment; then
        echo "❌ Docker não disponível"
        return 1
    fi
    
    # Verifica se o HD está montado antes de iniciar
    if ! is_hd_mounted; then
        echo "❌ HD não está montado. Monte primeiro com: painel mount"
        return 1
    fi
    
    cd "$DOCKER_COMPOSE_DIR" || return 1
    
    # Limpa containers antigos se --clean foi passado
    if [ "$clean_mode" = true ]; then
        echo ""
        clean_old_containers "$service"
        echo ""
    fi
    
    # Se um serviço específico foi informado
    if [ -n "$service" ]; then
        echo "▶️  Iniciando serviço específico: $service"
        if [ "$no_deps" = true ]; then
            echo "⚠️  Modo: Ignorando dependências (--no-deps)"
        fi
        echo ""
        
        if [ "$no_deps" = true ]; then
            docker compose up -d --no-deps "$service" 2>&1
            log_message "Serviço iniciado: $service (sem dependências)"
        else
            docker compose up -d "$service" 2>&1
            log_message "Serviço iniciado: $service"
        fi
    else
        # Inicia todos os serviços
        if load_docker_services; then
            echo "🚀 Iniciando todos os serviços: ${DOCKER_SERVICES[*]}"
            echo ""
            for service_item in "${DOCKER_SERVICES[@]}"; do
                echo "▶️  Iniciando: $service_item"
                docker compose up -d "$service_item" 2>&1
                log_message "Serviço iniciado: $service_item"
            done
        else
            echo "🚀 Iniciando todos os containers..."
            docker compose up -d 2>&1
            log_message "Todos os serviços iniciados"
        fi
    fi
    
    sleep 4
    echo ""
    echo "✅ Serviços Docker iniciados"
    echo ""
}

# ✅ FUNÇÃO: Reiniciar containers Docker (agora aceita serviço específico e flag --clean)
restart_docker_services() {
    service=""
    clean_mode=false
    
    # Parse de argumentos (aceita: service, --clean, ou ambos)
    for arg in "$@"; do
        if [ "$arg" = "--clean" ]; then
            clean_mode=true
        elif [ -n "$arg" ]; then
            service="$arg"
        fi
    done
    
    echo "🔄 Reiniciando serviços Docker..."
    echo ""
    
    if ! is_hd_mounted; then
        echo "❌ HD não está montado. Monte primeiro com: painel mount"
        return 1
    fi
    
    # Se um serviço específico foi informado
    if [ -n "$service" ]; then
        echo "🔄 Reiniciando serviço específico: $service"
        echo ""
        cd "$DOCKER_COMPOSE_DIR" || return 1
        
        if [ "$clean_mode" = true ]; then
            # Para, remove e inicia
            docker compose stop "$service" 2>&1
            log_message "Serviço parado para limpeza: $service"
            sleep 1
            clean_old_containers "$service"
            echo ""
            docker compose up -d "$service" 2>&1
            log_message "Serviço reiniciado após limpeza: $service"
        else
            # Restart simples
            docker compose restart "$service" 2>&1
            log_message "Serviço reiniciado: $service"
        fi
    else
        # Reinicia todos os serviços
        stop_docker_services
        sleep 2
        
        if [ "$clean_mode" = true ]; then
            echo ""
            clean_old_containers
            echo ""
        fi
        
        start_docker_services
    fi
}

# ✅ FUNÇÃO SIMPLIFICADA: Verificar se HD está montado
is_hd_mounted() {
    if mountpoint -q "$HD_MOUNT_POINT" 2>/dev/null; then
        return 0
    fi
    
    if grep -qs "$HD_MOUNT_POINT" /proc/mounts; then
        return 0
    fi
    
    return 1
}

# ✅ FUNÇÃO SIMPLIFICADA: Montar HD
mount_hd_simple() {
    echo "🔍 Verificando HD externo..."
    echo ""
    
    # Detecta o dispositivo automaticamente pelo UUID
    local HD_DEVICE=$(get_device_by_uuid)
    
    if [ -z "$HD_DEVICE" ]; then
        echo "❌ HD não detectado (UUID: $HD_UUID)"
        echo "💡 Verifique se o HD está conectado: lsblk"
        return 1
    fi
    
    # Verifica se já está montado
    if is_hd_mounted; then
        echo "✅ HD já está montado em: $HD_MOUNT_POINT"
        echo "📍 Dispositivo: $HD_DEVICE"
        return 0
    fi
    
    echo "✅ HD detectado: $HD_DEVICE"
    echo ""
    
    # Criar ponto de montagem se não existir
    sudo mkdir -p "$HD_MOUNT_POINT"
    sudo chown mateus:mateus "$HD_MOUNT_POINT"
    
    echo "🔄 Montando HD..."
    echo ""
    
    # Tenta montar pelo UUID (mais confiável)
    if sudo mount UUID="$HD_UUID" "$HD_MOUNT_POINT"; then
        echo "✅ HD montado com sucesso em: $HD_MOUNT_POINT"
        echo "📍 Dispositivo: $HD_DEVICE"
        log_message "HD montado: $HD_DEVICE (UUID: $HD_UUID) em $HD_MOUNT_POINT"
        return 0
    else
        echo "❌ Erro ao montar HD"
        return 1
    fi
}

# ✅ FUNÇÃO: Desmontar HD forçado
unmount_hd_forced() {
    echo "🔄 Desmontando HD..."
    echo ""
    
    # Para containers Docker se estiverem rodando
    stop_docker_services
    sleep 3  # Dar tempo para containers liberarem arquivos
    
    # Verifica se há processos usando o HD
    if command -v lsof &> /dev/null && mountpoint -q "$HD_MOUNT_POINT" 2>/dev/null; then
        if lsof "$HD_MOUNT_POINT" 2>/dev/null | grep -q "$HD_MOUNT_POINT"; then
            echo "⚠️  Processos ainda estão usando o HD:"
            lsof "$HD_MOUNT_POINT" 2>/dev/null | tail -10
            echo ""
            read -p "Continuar mesmo assim? (s/N): " confirm
            if [[ ! "$confirm" =~ ^[sS]$ ]]; then
                echo "❌ Operação cancelada"
                return 1
            fi
        fi
    fi
    
    # Sync antes de desmontar (flush buffers)
    sync
    
    # Tenta desmontar o ponto de montagem específico
    if mountpoint -q "$HD_MOUNT_POINT" 2>/dev/null; then
        if sudo umount "$HD_MOUNT_POINT" 2>/dev/null; then
            echo "✅ HD desmontado de $HD_MOUNT_POINT"
        else
            echo "⚠️  Desmontagem normal falhou, tentando lazy unmount..."
            sudo umount -l "$HD_MOUNT_POINT"
            echo "✅ Lazy unmount aplicado"
        fi
    fi
    
    echo ""
    echo "✅ Operação de desmontagem concluída"
}

# ✅ FUNÇÃO DE KEEPALIVE MELHORADA
keepalive_hd_optimized() {
    echo "🔋 Iniciando modo keepalive..."
    echo "📝 Monitorando HD e containers Docker a cada 30 segundos"
    echo "💡 Pressione Ctrl+C para parar"
    echo ""
    
    log_message "Iniciando modo keepalive"
    
    # Carrega serviços uma vez no início
    load_docker_services
    
    # Contadores para otimização
    local retry_count=0
    local max_retries=3
    local touch_counter=0
    
    while true; do
        if ! is_hd_mounted; then
            ((retry_count++))
            
            echo "$(date '+%H:%M:%S') ⚠️  HD não montado, tentando remontar... (tentativa $retry_count/$max_retries)"
            log_message "Keepalive: HD não montado, tentando remontar (tentativa $retry_count)"
            
            # Se falhou muitas vezes, pausa por 5 minutos
            if [ $retry_count -ge $max_retries ]; then
                echo "❌ ERRO: Falha após $max_retries tentativas consecutivas"
                echo "⏸️  Pausando por 5 minutos antes de tentar novamente..."
                log_message "Keepalive: Múltiplas falhas detectadas, pausando por 5 minutos"
                retry_count=0
                sleep 300  # 5 minutos
                continue
            fi
            
            # Tenta montar
            if mount_hd_simple; then
                echo "✅ Reconexão bem-sucedida!"
                log_message "Keepalive: HD remontado com sucesso"
                retry_count=0  # Reset contador em caso de sucesso
                
                # Inicia os containers após montar o HD
                start_docker_services
            else
                echo "❌ Falha na reconexão, tentando novamente em 30s..."
            fi
        else
            retry_count=0  # Reset contador quando HD está montado
            
            # Touch apenas a cada 10 minutos (20 ciclos de 30s)
            ((touch_counter++))
            if [ $((touch_counter % 20)) -eq 0 ]; then
                touch "$HD_MOUNT_POINT/.keepalive" 2>/dev/null
            fi
            
            # Verifica se containers deveriam estar rodando mas não estão
            if check_docker_environment && [ ${#DOCKER_SERVICES[@]} -gt 0 ]; then
                local stopped_services=()
                
                for service in "${DOCKER_SERVICES[@]}"; do
                    # Usa grep -x para match exato (evita false positives)
                    if ! docker ps --format "{{.Names}}" | grep -qx "$service"; then
                        stopped_services+=("$service")
                    fi
                done
                
                if [ ${#stopped_services[@]} -gt 0 ]; then
                    echo "⚠️  Serviços parados detectados: ${stopped_services[*]}"
                    echo "🔄 Reiniciando serviços..."
                    for service in "${stopped_services[@]}"; do
                        start_docker_services "$service"
                    done
                fi
            fi
            
            echo "$(date '+%H:%M:%S') ✅ HD montado e ativo"
        fi
        
        sleep 30
    done
}

# ✅ FUNÇÃO DE STATUS COMPLETA
show_status_optimized() {
    echo "📊 STATUS DO SISTEMA"
    echo "===================="
    echo ""
    
    # Status do HD
    if is_hd_mounted; then
        echo "✅ HD: MONTADO em $HD_MOUNT_POINT"
        df -h "$HD_MOUNT_POINT" | tail -1
    else
        echo "❌ HD: NÃO MONTADO"
        echo "💡 Dispositivo: $HD_DEVICE"
    fi
    
    echo ""
    echo "===================="
    echo ""
    
    # Status Docker
    if check_docker_environment; then
        echo "🐳 DOCKER:"
        
        # Mostra serviços configurados
        if load_docker_services; then
            echo "📋 Serviços no compose: ${DOCKER_SERVICES[*]}"
        fi
        
        echo ""
        
        if docker ps --quiet | read; then
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        else
            echo "   Nenhum container em execução"
        fi
    else
        echo "❌ Docker não disponível"
    fi
    
    echo ""
}

# ✅ FUNÇÃO: Verificar montagens ativas
check_mounts() {
    echo "📋 MONTAGENS ATIVAS:"
    echo "===================="
    echo ""
    findmnt -r | grep -E "(sdb|$HD_MOUNT_POINT)" || echo "   Nenhuma montagem do HD encontrada"
    
    echo ""
    echo "📋 DISPOSITIVOS DE BLOCO:"
    echo "========================"
    echo ""
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,LABEL,UUID
    echo ""
}

# ✅ FUNÇÃO: Corrigir permissões e estrutura
fix_mount_point() {
    echo "🔧 Corrigindo ponto de montagem..."
    echo ""
    
    # Remove o ponto de montagem se existir
    if [ -d "$HD_MOUNT_POINT" ]; then
        sudo rmdir "$HD_MOUNT_POINT" 2>/dev/null
    fi
    
    # Cria novo ponto de montagem
    sudo mkdir -p "$HD_MOUNT_POINT"
    sudo chown mateus:mateus "$HD_MOUNT_POINT"
    sudo chmod 755 "$HD_MOUNT_POINT"
    
    echo "✅ Ponto de montagem corrigido: $HD_MOUNT_POINT"
}

# ✅ FUNÇÃO SEGURA PARA COMANDOS DOCKER
docker_compose_safe() {
    local command="$1"
    local service="$2"
    
    if ! check_docker_environment; then
        echo "❌ Ambiente Docker não disponível"
        return 1
    fi
    
    cd "$DOCKER_COMPOSE_DIR" || {
        echo "❌ Não foi possível acessar: $DOCKER_COMPOSE_DIR"
        return 1
    }
    
    case "$command" in
        "up")
            if [ -n "$service" ]; then
                docker compose up -d "$service"
            else
                docker compose up -d
            fi
            ;;
        "stop"|"restart"|"logs")
            if [ -n "$service" ]; then
                docker compose "$command" "$service"
            else
                echo "❌ Serviço não especificado."
                return 1
            fi
            ;;
        *)
            docker compose "$command"
            ;;
    esac
}

# =============================================================================
# COMANDOS PRINCIPAIS - VERSÃO COMPLETA
# =============================================================================

case "$1" in
    "mount")
        mount_hd_simple
        ;;
    "unmount")
        unmount_hd_forced
        ;;
    "status")
        show_status_optimized
        ;;
    "keepalive")
        keepalive_hd_optimized
        ;;
    "check")
        check_mounts
        ;;
    "fix")
        fix_mount_point
        ;;
    "start")
        start_docker_services "$2" "$3" "$4"
        ;;
    "stop")
        stop_docker_services "$2"
        ;;
    "restart")
        restart_docker_services "$2" "$3"
        ;;
    "clean")
        if [ -n "$2" ]; then
            clean_old_containers "$2"
        else
            clean_old_containers
        fi
        ;;
    "ps")
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;
    "logs")
        if [ -n "$2" ]; then
            # Validar se serviço existe
            if load_docker_services && [[ " ${DOCKER_SERVICES[@]} " =~ " $2 " ]]; then
                cd "$DOCKER_COMPOSE_DIR" && docker compose logs "$2" "${@:3}"
            else
                echo "❌ Serviço '$2' não encontrado"
                echo "💡 Serviços disponíveis:"
                echo ""
                if load_docker_services; then
                    printf "  - %s\n" "${DOCKER_SERVICES[@]}"
                fi
                exit 1
            fi
        else
            echo "❌ Especifique um serviço: painel logs <servico> [-f]"
            echo "💡 Use 'painel services' para ver serviços disponíveis"
            exit 1
        fi
        ;;
    "services")
        echo "📋 Serviços disponíveis no docker-compose:"
        echo ""
        if load_docker_services; then
            for service in "${DOCKER_SERVICES[@]}"; do
                echo "  - $service"
            done
        else
            cd "$DOCKER_COMPOSE_DIR" && docker compose config --services
        fi
        echo ""
        ;;
    "health")
        echo "🏥 HEALTH CHECK DOS SERVIÇOS"
        echo "============================"
        echo ""
        
        if ! load_docker_services; then
            echo "❌ Não foi possível carregar serviços"
            exit 1
        fi
        
        for service in "${DOCKER_SERVICES[@]}"; do
            health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null)
            status=$(docker inspect --format='{{.State.Status}}' "$service" 2>/dev/null)
            
            if [ -z "$status" ]; then
                echo "❌ $service: NÃO EXISTE"
            elif [ "$status" != "running" ]; then
                echo "🔴 $service: $status"
            elif [ -n "$health" ] && [ "$health" != "healthy" ]; then
                echo "⚠️  $service: running mas $health"
            else
                echo "✅ $service: OK"
            fi
        done
        
        echo ""
        ;;
    "stats")
        echo "📊 USO DE RECURSOS (pressione Ctrl+C para sair)"
        echo ""
        if [ -n "$2" ]; then
            # Stats de serviço específico
            docker stats "$2"
        else
            # Stats de todos os containers
            docker stats
        fi
        ;;
    "pull")
        echo "⬇️  ATUALIZANDO IMAGENS"
        echo ""
        if ! check_docker_environment; then
            echo "❌ Docker não disponível"
            exit 1
        fi
        cd "$DOCKER_COMPOSE_DIR" || exit 1
        docker compose pull
        echo ""
        echo "✅ Imagens atualizadas!"
        echo "💡 Use 'painel restart' para aplicar as atualizações"
        ;;
    "rebuild")
        echo "🔨 REBUILD DE CONTAINERS"
        echo ""
        if ! is_hd_mounted; then
            echo "❌ HD não está montado"
            exit 1
        fi
        cd "$DOCKER_COMPOSE_DIR" || exit 1
        
        # Por padrão usa --no-cache, a menos que --cache seja passado
        no_cache="--no-cache"
        service=""
        for arg in "$2" "$3"; do
            if [ "$arg" = "--cache" ]; then
                no_cache=""
                echo "💾 Modo: COM CACHE (rebuild rápido)"
                echo ""
            elif [ -n "$arg" ]; then
                service="$arg"
            fi
        done
        
        # Mostra modo padrão se não passou --cache
        if [ "$no_cache" = "--no-cache" ]; then
            echo "🚫 Modo: SEM CACHE (rebuild completo)"
            echo ""
        fi
        
        if [ -n "$service" ]; then
            echo "🔨 Rebuild do serviço: $service"
            docker compose build $no_cache "$service"
            docker compose up -d "$service"
        else
            echo "🔨 Rebuild de todos os serviços"
            docker compose build $no_cache
            docker compose up -d
        fi
        echo ""
        echo "✅ Rebuild concluído!"
        ;;
    "update")
        echo "🔄 ATUALIZAÇÃO COMPLETA"
        echo ""
        if ! is_hd_mounted; then
            echo "❌ HD não está montado"
            exit 1
        fi
        cd "$DOCKER_COMPOSE_DIR" || exit 1
        echo "⬇️  1/3: Baixando imagens atualizadas..."
        docker compose pull
        echo ""
        echo "🛑 2/3: Parando containers..."
        docker compose down
        echo ""
        echo "🚀 3/3: Iniciando containers atualizados..."
        docker compose up -d
        echo ""
        echo "✅ Atualização completa!"
        ;;
    "networks")
        echo "🌐 REDES DOCKER"
        echo "==============="
        echo ""
        docker network ls
        echo ""
        ;;
    "volumes")
        echo "💾 VOLUMES DOCKER"
        echo "================="
        echo ""
        docker volume ls
        echo ""
        ;;
    "prune")
        echo "🧹 LIMPEZA DE RECURSOS NÃO UTILIZADOS"
        echo ""
        read -p "Isso removerá containers parados, redes não usadas, imagens órfãs e cache. Continuar? (s/N): " confirm
        if [[ "$confirm" =~ ^[sS]$ ]]; then
            echo ""
            echo "🗑️  Removendo containers parados..."
            docker container prune -f
            echo ""
            echo "🗑️  Removendo redes não utilizadas..."
            docker network prune -f
            echo ""
            echo "🗑️  Removendo imagens órfãs..."
            docker image prune -f
            echo ""
            echo "🗑️  Removendo cache de build..."
            docker builder prune -f
            echo ""
            echo "✅ Limpeza concluída!"
        else
            echo "❌ Operação cancelada"
        fi
        ;;
    "diagnose")
        echo "🔍 DIAGNÓSTICO COMPLETO:"
        echo ""
        echo "HD:"
        echo "  UUID: $HD_UUID"
        echo "  Label: $HD_LABEL"
        detected_device=$(get_device_by_uuid)
        if [ -n "$detected_device" ]; then
            echo "  Dispositivo detectado: $detected_device"
        else
            echo "  Dispositivo detectado: ❌ NÃO ENCONTRADO"
        fi
        echo "  Ponto de montagem: $HD_MOUNT_POINT"
        echo "  Montado: $(is_hd_mounted && echo 'SIM' || echo 'NÃO')"
        if is_hd_mounted; then
            echo "  Uso do disco:"
            df -h "$HD_MOUNT_POINT" | tail -1 | awk '{print "    "$2" total, "$3" usado, "$4" livre ("$5" usado)"}'
        fi
        echo ""
        echo "Docker:"
        echo "  Docker disponível: $(check_docker_environment && echo 'SIM' || echo 'NÃO')"
        echo "  Containers rodando: $(docker ps -q | wc -l)"
        if load_docker_services; then
            echo "  Serviços detectados: ${DOCKER_SERVICES[*]}"
        fi
        echo ""
        ;;
    "force-mount")
        echo "⚡ MONTAGEM FORÇADA"
        echo ""
        unmount_hd_forced
        sleep 2
        fix_mount_point
        sleep 1
        mount_hd_simple
        ;;
    *)
        echo "🎛️  COMANDOS DISPONÍVEIS:"
        echo ""
        echo "  mount       - Montar HD"
        echo "  unmount     - Desmontar HD" 
        echo "  status      - Status completo do sistema"
        echo "  keepalive   - Modo keepalive (manter HD ativo)"
        echo "  check       - Ver montagens"
        echo "  fix         - Corrigir ponto de montagem"
        echo ""
        echo "🐳 GERENCIAMENTO DOCKER:"
        echo "  start       - Iniciar containers (painel start [servico] [--clean] [--no-deps])"
        echo "  stop        - Parar containers (painel stop [servico])"
        echo "  restart     - Reiniciar containers (painel restart [servico] [--clean])"
        echo "  clean       - Remover containers antigos (painel clean [servico])"
        echo "  ps          - Containers em execução"
        echo "  logs        - Ver logs (painel logs <servico> [-f])"
        echo "  stats       - Uso de recursos (painel stats [servico])"
        echo "  health      - Verificar saúde dos containers"
        echo ""
        echo "💡 Use --clean ao iniciar/reiniciar para remover containers antigos"
        echo "   Use --no-deps ao iniciar para ignorar dependências"
        echo "   Exemplo: painel start cloudflared --no-deps"
        echo ""
        echo "🔄 MANUTENÇÃO DOCKER:"
        echo "  services    - Listar serviços disponíveis"
        echo "  pull        - Baixar imagens atualizadas"
        echo "  rebuild     - Rebuild de containers SEM cache (painel rebuild [servico] [--cache])"
        echo "  update      - Atualização completa (pull + restart)"
        echo "  networks    - Listar redes Docker"
        echo "  volumes     - Listar volumes Docker"
        echo "  prune       - Limpar recursos não utilizados"
        echo ""
        echo "🔧 UTILITÁRIOS:"
        echo "  diagnose    - Diagnóstico completo"
        echo "  force-mount - Forçar remontagem"
        echo ""
        ;;
esac
