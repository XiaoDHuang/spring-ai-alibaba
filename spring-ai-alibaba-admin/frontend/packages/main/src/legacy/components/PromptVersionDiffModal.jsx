import React, { useEffect, useState, useMemo } from 'react';
import {
  Modal,
  Select,
  Button,
  Spin,
  Empty,
  Space,
  Tag,
  Typography,
  message
} from 'antd';
import { SwapOutlined } from '@ant-design/icons';
import { getPromptVersions, getPromptVersionDiff } from '../services/prompt';

const { Text, Title } = Typography;

/**
 * Renders a simple line-level diff between two strings.
 * Returns an array of { kind, text } for line-by-line rendering.
 */
function computeLineDiff(textA, textB) {
  const linesA = (textA || '').split('\n');
  const linesB = (textB || '').split('\n');
  const maxLen = Math.max(linesA.length, linesB.length);
  const result = [];
  for (let i = 0; i < maxLen; i++) {
    const a = linesA[i] ?? null;
    const b = linesB[i] ?? null;
    if (a === b) {
      result.push({ kind: 'UNCHANGED', text: a });
    } else if (a === null) {
      result.push({ kind: 'ADDED', text: b });
    } else if (b === null) {
      result.push({ kind: 'REMOVED', text: a });
    } else {
      result.push({ kind: 'REMOVED', text: a });
      result.push({ kind: 'ADDED', text: b });
    }
  }
  return result;
}

const DIFF_LINE_STYLE = {
  UNCHANGED: { background: 'transparent', padding: '2px 8px', fontFamily: 'monospace', fontSize: 13 },
  ADDED:     { background: '#e6ffec', padding: '2px 8px', fontFamily: 'monospace', fontSize: 13 },
  REMOVED:   { background: '#ffebe9', padding: '2px 8px', fontFamily: 'monospace', fontSize: 13 },
};

const DIFF_PREFIX = { ADDED: '+ ', REMOVED: '- ', UNCHANGED: '  ' };

/**
 * Version diff modal — P11.
 *
 * Opens from the Prompt detail page.  User picks two versions from a
 * checkbox-enabled Select, fires GET /api/prompt/version/diff, and
 * sees three sections (template / variables / modelConfig) with
 * per-field changed indicators.
 */
const PromptVersionDiffModal = ({ promptKey, visible, onClose }) => {
  const [versions, setVersions] = useState([]);
  const [selectedA, setSelectedA] = useState(null);
  const [selectedB, setSelectedB] = useState(null);
  const [loadingVersions, setLoadingVersions] = useState(false);
  const [loadingDiff, setLoadingDiff] = useState(false);
  const [diffResult, setDiffResult] = useState(null);

  // Load version list on open
  useEffect(() => {
    if (!visible || !promptKey) return;
    setLoadingVersions(true);
    getPromptVersions({ promptKey, pageNo: 1, pageSize: 100 })
      .then(res => {
        const items = res?.data?.pageItems || [];
        setVersions(items);
        // Default: A = latest release, B = latest pre
        const release = items.find(v => v.status === 'release');
        const pre = items.find(v => v.status === 'pre');
        if (release) setSelectedA(release.version);
        if (pre) setSelectedB(pre.version);
        if (!release && items.length >= 1) setSelectedA(items[0].version);
        if (!pre && items.length >= 2) setSelectedB(items[1].version);
      })
      .catch(() => message.error('加载版本列表失败'))
      .finally(() => setLoadingVersions(false));
  }, [visible, promptKey]);

  // Called when user clicks "Compare"
  const handleCompare = () => {
    if (!selectedA || !selectedB) {
      message.warning('请选择两个版本');
      return;
    }
    setLoadingDiff(true);
    setDiffResult(null);
    getPromptVersionDiff({ promptKey, versionA: selectedA, versionB: selectedB })
      .then(res => {
        if (res?.data) setDiffResult(res.data);
        else message.error('对比失败，未返回数据');
      })
      .catch(err => {
        message.error('对比请求失败: ' + (err?.message || '未知错误'));
      })
      .finally(() => setLoadingDiff(false));
  };

  // Disable options when 2 versions are already selected
  const handleVersionChange = (values) => {
    if (values.length === 0) return;
    if (values.length === 1) {
      // First selection → assign to A
      setSelectedA(values[0]);
      setSelectedB(null);
      setDiffResult(null);
    } else if (values.length === 2) {
      setSelectedA(values[0]);
      setSelectedB(values[1]);
      setDiffResult(null);
    }
  };

  const selectedValues = [selectedA, selectedB].filter(Boolean);

  const versionOptions = useMemo(() =>
    versions.map(v => ({
      label: `${v.version} ${v.status === 'release' ? '(release)' : '(pre)'}`,
      value: v.version,
    })), [versions]);

  const renderMeta = (meta, label) => (
    <div style={{ marginBottom: 8 }}>
      <Tag color={meta.status === 'release' ? 'green' : 'orange'}>{meta.status}</Tag>
      <Text type="secondary">
        {label}: {meta.version} · {new Date(meta.createTime).toLocaleString()}
      </Text>
    </div>
  );

  const renderDiffItem = (diffItem, title) => (
    <div style={{ marginBottom: 16 }}>
      <Title level={5}>
        {title}
        {diffItem.changed
          ? <Tag color="red" style={{ marginLeft: 8 }}>有变更</Tag>
          : <Tag color="default" style={{ marginLeft: 8 }}>无变化</Tag>
        }
      </Title>
      {!diffItem.changed && (
        <Text type="secondary" style={{ display: 'block', marginBottom: 8 }}>
          内容相同
        </Text>
      )}
      {diffItem.changed && (
        <div style={{ maxHeight: 300, overflow: 'auto', border: '1px solid #f0f0f0', borderRadius: 4 }}>
          {computeLineDiff(diffItem.valueA, diffItem.valueB).map((line, i) => (
            <div key={i} style={DIFF_LINE_STYLE[line.kind]}>
              {DIFF_PREFIX[line.kind]}{line.text}
            </div>
          ))}
        </div>
      )}
    </div>
  );

  return (
    <Modal
      title={<Space><SwapOutlined /> 版本对比</Space>}
      open={visible}
      onCancel={onClose}
      width={900}
      footer={null}
      destroyOnClose
    >
      <Spin spinning={loadingVersions} tip="加载版本列表...">
        <Space direction="vertical" style={{ width: '100%' }}>
          {/* Selector */}
          <Space style={{ width: '100%' }} align="start">
            <Select
              mode="multiple"
              style={{ minWidth: 360 }}
              placeholder="请选择两个版本"
              maxTagCount={2}
              value={selectedValues}
              onChange={handleVersionChange}
              options={versionOptions}
            />
            <Button
              type="primary"
              onClick={handleCompare}
              loading={loadingDiff}
              disabled={selectedValues.length !== 2}
            >
              对比
            </Button>
          </Space>

          {/* Diff Result */}
          {loadingDiff && (
            <div style={{ textAlign: 'center', padding: 40 }}>
              <Spin tip="正在对比..." />
            </div>
          )}

          {!loadingDiff && diffResult && (
            <>
              <Space style={{ marginTop: 16 }}>
                {renderMeta(diffResult.versionA, '版本 A')}
                {renderMeta(diffResult.versionB, '版本 B')}
              </Space>

              {renderDiffItem(diffResult.diffs.template, 'Template')}
              {renderDiffItem(diffResult.diffs.variables, 'Variables')}
              {renderDiffItem(diffResult.diffs.modelConfig, 'Model Config')}
            </>
          )}

          {!loadingDiff && !diffResult && (
            <Empty description="请选择两个版本后点击对比" />
          )}
        </Space>
      </Spin>
    </Modal>
  );
};

export default PromptVersionDiffModal;
