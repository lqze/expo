import { css } from '@emotion/react';
import { borderRadius, iconSize, theme } from '@expo/styleguide';
import React, { ComponentType, PropsWithChildren } from 'react';

import { IconProps, ErrorIcon, InfoIcon, WarningIcon } from '~/ui/foundations/icons';

type CalloutType = 'info' | 'warning' | 'error';

type CalloutProps = PropsWithChildren<{
  type?: CalloutType;
  icon?: ComponentType<IconProps> | string;
}>;

export const Callout = ({ type = 'info', icon, children, ...rest }: CalloutProps) => {
  const Icon = icon || getCalloutIcon(type);
  return (
    <div css={[containerStyle, getCalloutColor(type)]} {...rest}>
      <i css={iconStyle}>{typeof icon === 'string' ? icon : <Icon size={iconSize.small} />}</i>
      <div css={contentStyle}>{children}</div>
    </div>
  );
};

function getCalloutColor(type: CalloutType) {
  switch (type) {
    case 'warning':
      return warningColorStyle;
    case 'error':
      return errorColorStyle;
    default:
      return null;
  }
}

function getCalloutIcon(type: CalloutType) {
  switch (type) {
    case 'warning':
      return WarningIcon;
    case 'error':
      return ErrorIcon;
    default:
      return InfoIcon;
  }
}

const containerStyle = css({
  backgroundColor: theme.background.secondary,
  border: `1px solid ${theme.border.default}`,
  borderRadius: borderRadius.medium,
  display: 'flex',
  padding: '1rem',
});

const iconStyle = css({
  fontStyle: 'normal',
  marginRight: '0.5rem',
  userSelect: 'none',
});

// Markdown adds unnecessary paragraphs within the callout component,
// we need to forcefully remove the bottom marging on the last (or only) paragraph
const contentStyle = css({
  'p:last-child': {
    marginBottom: '0 !important', // TODO(cedric): Find an alternative for important
  },
});

const warningColorStyle = css({
  backgroundColor: theme.background.warning,
  borderColor: theme.border.warning,
});

const errorColorStyle = css({
  backgroundColor: theme.background.error,
  borderColor: theme.border.error,
});
