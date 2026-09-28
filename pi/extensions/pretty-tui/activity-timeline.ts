export type ActivityMemberKind = "tool" | "thinking" | "update";
export type ActivitySeverity = "info" | "warning" | "error";

export type ActivityMember = {
  id: string;
  kind: ActivityMemberKind;
  toolCallId?: string;
  toolName?: string;
  messageKey?: string;
  thinking?: string;
  updateKey?: string;
  updateTitle?: string;
  updateContent?: string;
  updateSeverity?: ActivitySeverity;
  persistent?: boolean;
};

export type ActivityGroup = {
  id: string;
  members: ActivityMember[];
  toolCallIds: string[];
  thoughtCount: number;
  hardBoundarySplit?: boolean;
};

const toolMemberId = (toolCallId: string) => `tool:${toolCallId}`;
const thinkingMemberId = (messageKey: string) => `thinking:${messageKey}`;
const updateMemberId = (updateKey: string) => `update:${updateKey}`;

/**
 * Transcript-first activity grouping. The timeline owns chronology and hard
 * boundaries; renderers only project its groups into Pi components.
 */
export class ActivityTimeline {
  private groupsById = new Map<string, ActivityGroup>();
  private membersById = new Map<string, ActivityMember>();
  private memberGroups = new Map<string, string>();
  private toolMembers = new Map<string, string>();
  private thinkingMembers = new Map<string, string>();
  private updateMembers = new Map<string, string>();
  private settledGroups = new Set<string>();
  private currentGroupId?: string;
  private sequence = 0;

  clear(): void {
    this.groupsById.clear();
    this.membersById.clear();
    this.memberGroups.clear();
    this.toolMembers.clear();
    this.thinkingMembers.clear();
    this.updateMembers.clear();
    this.settledGroups.clear();
    this.currentGroupId = undefined;
    this.sequence = 0;
  }

  /**
   * Ends the current group. Because every hard transcript boundary routes here,
   * a closed group can never receive further members, which makes this the
   * completion signal for groups that have no durable tool summary.
   */
  boundary(settled = true): void {
    if (settled && this.currentGroupId) this.settledGroups.add(this.currentGroupId);
    this.currentGroupId = undefined;
  }

  isSettled(groupId: string): boolean {
    return this.settledGroups.has(groupId);
  }

  private ensureCurrentGroup(): ActivityGroup {
    if (this.currentGroupId) {
      const current = this.groupsById.get(this.currentGroupId);
      if (current) return current;
    }
    const id = `activity:${++this.sequence}`;
    const group: ActivityGroup = {
      id,
      members: [],
      toolCallIds: [],
      thoughtCount: 0,
    };
    this.groupsById.set(id, group);
    this.currentGroupId = id;
    return group;
  }

  addTool(toolCallId: string, toolName: string): ActivityMember {
    const existingId = this.toolMembers.get(toolCallId);
    if (existingId) return this.member(existingId)!;
    const member: ActivityMember = {
      id: toolMemberId(toolCallId),
      kind: "tool",
      toolCallId,
      toolName,
    };
    const group = this.ensureCurrentGroup();
    group.members.push(member);
    group.toolCallIds.push(toolCallId);
    this.membersById.set(member.id, member);
    this.memberGroups.set(member.id, group.id);
    this.toolMembers.set(toolCallId, member.id);
    return member;
  }

  addThinking(messageKey: string, thinking: string): ActivityMember | undefined {
    const normalized = thinking.trim();
    if (!normalized) return undefined;
    const existingId = this.thinkingMembers.get(messageKey);
    if (existingId) {
      const existing = this.member(existingId);
      if (existing) existing.thinking = normalized;
      return existing;
    }
    const member: ActivityMember = {
      id: thinkingMemberId(messageKey),
      kind: "thinking",
      messageKey,
      thinking: normalized,
    };
    const group = this.ensureCurrentGroup();
    group.members.push(member);
    group.thoughtCount += 1;
    this.membersById.set(member.id, member);
    this.memberGroups.set(member.id, group.id);
    this.thinkingMembers.set(messageKey, member.id);
    return member;
  }

  addUpdate(
    updateKey: string,
    title: string,
    content: string,
    persistent: boolean,
    severity: ActivitySeverity = "info",
  ): ActivityMember | undefined {
    if (!this.currentGroupId) return undefined;
    return this.addUpdateToGroup(this.currentGroupId, updateKey, title, content, persistent, severity);
  }

  addPendingUpdate(
    updateKey: string,
    title: string,
    content: string,
    persistent: boolean,
    severity: ActivitySeverity = "info",
  ): ActivityMember {
    const existingId = this.updateMembers.get(updateKey);
    if (existingId) return this.member(existingId)!;
    const group = this.ensureCurrentGroup();
    return this.appendUpdate(group, updateKey, title, content, persistent, severity);
  }

  /**
   * A group can receive update members only once it holds real work. This is
   * the single definition of that condition: thinking counts even before any
   * tool has run, because an activity group is created by the first thought.
   */
  hasWork(group: ActivityGroup | undefined): boolean {
    return Boolean(group?.members.some(
      (member) => member.kind === "tool" || member.kind === "thinking",
    ));
  }

  addUpdateToGroup(
    groupId: string,
    updateKey: string,
    title: string,
    content: string,
    persistent: boolean,
    severity: ActivitySeverity = "info",
  ): ActivityMember | undefined {
    const existingId = this.updateMembers.get(updateKey);
    if (existingId) return this.member(existingId);
    const group = this.groupsById.get(groupId);
    if (!this.hasWork(group)) return undefined;
    return this.appendUpdate(group!, updateKey, title, content, persistent, severity);
  }

  private appendUpdate(
    group: ActivityGroup,
    updateKey: string,
    title: string,
    content: string,
    persistent: boolean,
    severity: ActivitySeverity = "info",
  ): ActivityMember {
    const member: ActivityMember = {
      id: updateMemberId(updateKey),
      kind: "update",
      updateKey,
      updateTitle: title.trim() || "Update",
      updateContent: content.trim(),
      updateSeverity: severity,
      persistent,
    };
    group.members.push(member);
    this.membersById.set(member.id, member);
    this.memberGroups.set(member.id, group.id);
    this.updateMembers.set(updateKey, member.id);
    return member;
  }

  currentGroup(): ActivityGroup | undefined {
    return this.currentGroupId ? this.groupsById.get(this.currentGroupId) : undefined;
  }

  groups(): ActivityGroup[] {
    return [...this.groupsById.values()];
  }

  group(groupId: string): ActivityGroup | undefined {
    return this.groupsById.get(groupId);
  }

  member(memberId: string): ActivityMember | undefined {
    return this.membersById.get(memberId);
  }

  groupForMember(memberId: string): ActivityGroup | undefined {
    const groupId = this.memberGroups.get(memberId);
    return groupId ? this.groupsById.get(groupId) : undefined;
  }

  memberForTool(toolCallId: string): ActivityMember | undefined {
    const memberId = this.toolMembers.get(toolCallId);
    return memberId ? this.member(memberId) : undefined;
  }

  memberForThinking(messageKey: string): ActivityMember | undefined {
    const memberId = this.thinkingMembers.get(messageKey);
    return memberId ? this.member(memberId) : undefined;
  }

  memberForUpdate(updateKey: string): ActivityMember | undefined {
    const memberId = this.updateMembers.get(updateKey);
    return memberId ? this.member(memberId) : undefined;
  }

  /**
   * Releases a claimed update and splits the group at that point, so a native
   * custom renderer can take the message over without the remaining members
   * being reordered around it.
   */
  removeUpdate(updateKey: string): boolean {
    const memberId = this.updateMembers.get(updateKey);
    if (!memberId) {
      this.boundary();
      return false;
    }
    const groupId = this.memberGroups.get(memberId);
    const group = groupId ? this.groupsById.get(groupId) : undefined;
    if (group) {
      const index = group.members.findIndex((member) => member.id === memberId);
      if (index >= 0) {
        const following = group.members.slice(index + 1);
        group.members = group.members.slice(0, index);
        group.hardBoundarySplit = true;
        group.toolCallIds = group.members
          .filter((member) => member.kind === "tool" && member.toolCallId)
          .map((member) => member.toolCallId!);
        group.thoughtCount = group.members.filter((member) => member.kind === "thinking").length;

        if (following.length > 0) {
          const nextId = `activity:${++this.sequence}`;
          const next: ActivityGroup = {
            id: nextId,
            members: following,
            toolCallIds: following
              .filter((member) => member.kind === "tool" && member.toolCallId)
              .map((member) => member.toolCallId!),
            thoughtCount: following.filter((member) => member.kind === "thinking").length,
            hardBoundarySplit: true,
          };
          const ordered = new Map<string, ActivityGroup>();
          for (const [id, existing] of this.groupsById) {
            ordered.set(id, existing);
            if (id === group.id) ordered.set(next.id, next);
          }
          this.groupsById = ordered;
          for (const member of following) this.memberGroups.set(member.id, next.id);
          if (this.currentGroupId === group.id) this.currentGroupId = next.id;
        } else if (this.currentGroupId === group.id) {
          this.currentGroupId = undefined;
        }
      }
      if (group.members.length === 0) {
        this.groupsById.delete(group.id);
        if (this.currentGroupId === group.id) this.currentGroupId = undefined;
      }
    }
    this.updateMembers.delete(updateKey);
    this.memberGroups.delete(memberId);
    this.membersById.delete(memberId);
    return true;
  }

  groupForTool(toolCallId: string): ActivityGroup | undefined {
    const member = this.memberForTool(toolCallId);
    return member ? this.groupForMember(member.id) : undefined;
  }

  groupForThinking(messageKey: string): ActivityGroup | undefined {
    const member = this.memberForThinking(messageKey);
    return member ? this.groupForMember(member.id) : undefined;
  }

  groupForUpdate(updateKey: string): ActivityGroup | undefined {
    const member = this.memberForUpdate(updateKey);
    return member ? this.groupForMember(member.id) : undefined;
  }
}

export const assistantMessageKey = (message: any): string => {
  const timestamp = message?.timestamp;
  if (typeof timestamp === "number" || typeof timestamp === "string") return String(timestamp);
  const firstToolCall = Array.isArray(message?.content)
    ? message.content.find((item: any) => item?.type === "toolCall" && item.id)?.id
    : undefined;
  return firstToolCall ? `tool-message:${firstToolCall}` : `message:${JSON.stringify(message?.content ?? "")}`;
};

export const thinkingText = (message: any): string => {
  if (!Array.isArray(message?.content)) return "";
  return message.content
    .filter((item: any) => item?.type === "thinking" && typeof item.thinking === "string")
    .map((item: any) => item.thinking.trim())
    .filter(Boolean)
    .join("\n\n");
};

export const visibleAssistantText = (message: any): boolean =>
  typeof message?.content === "string"
    ? message.content.trim().length > 0
    : Array.isArray(message?.content) && message.content.some(
      (item: any) => item?.type === "text" && typeof item.text === "string" && item.text.trim().length > 0,
    );

export const assistantTerminalState = (message: any): boolean =>
  message?.role === "assistant" && ["error", "aborted", "length"].includes(message?.stopReason);
