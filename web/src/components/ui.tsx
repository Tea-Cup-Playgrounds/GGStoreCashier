// Small UI kit shared by every page: buttons, form controls, tables, modal, toasts, states.
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type SelectHTMLAttributes,
  type TextareaHTMLAttributes,
} from 'react';
import { AlertTriangle, Loader2, X } from 'lucide-react';
import { errorMessage } from '../api/client';

export const cx = (...classes: Array<string | false | null | undefined>) => classes.filter(Boolean).join(' ');

// ── Buttons ───────────────────────────────────────────────────────────────────

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';
// Flat: solid fills or a solid 2px outline, bold labels, no shadows. Disabled states keep a visible
// outline so the control is still recognisable as a button.
const VARIANTS: Record<Variant, string> = {
  primary:
    'border-2 border-brand-500 bg-brand-500 text-ink-900 hover:border-brand-600 hover:bg-brand-600 active:bg-brand-400 disabled:border-stone-200 disabled:bg-stone-200 disabled:text-stone-400',
  secondary:
    'border-2 border-ink-900 bg-white text-ink-900 hover:bg-brand-100 active:bg-brand-200 disabled:border-stone-300 disabled:bg-white disabled:text-stone-400',
  ghost: 'border-2 border-transparent text-ink-900 hover:bg-stone-200/70 disabled:text-stone-400',
  danger: 'border-2 border-red-600 bg-red-600 text-white hover:border-red-700 hover:bg-red-700 disabled:border-red-200 disabled:bg-red-200',
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  size?: 'sm' | 'md';
  loading?: boolean;
  icon?: ReactNode;
}

export function Button({ variant = 'secondary', size = 'md', loading, icon, className, children, disabled, ...rest }: ButtonProps) {
  return (
    <button
      type="button"
      {...rest}
      disabled={disabled || loading}
      className={cx(
        'inline-flex items-center justify-center gap-1.5 rounded-md font-bold whitespace-nowrap transition-colors disabled:cursor-not-allowed',
        // Icon-only (no label): square, so the icon is not squeezed by the text padding.
        children == null ? (size === 'sm' ? 'size-8' : 'size-10') : size === 'sm' ? 'h-8 px-3 text-sm' : 'h-10 px-4 text-sm',
        VARIANTS[variant],
        className,
      )}
    >
      {loading ? <Loader2 className="size-4 animate-spin" /> : icon}
      {children}
    </button>
  );
}

// ── Form controls ─────────────────────────────────────────────────────────────

// 2px outline that turns black with a solid yellow halo on focus (flat: no blur).
const CONTROL =
  'w-full rounded-md border-2 border-stone-300 bg-white px-3 text-sm font-medium text-ink-900 placeholder:font-normal placeholder:text-stone-400 hover:border-stone-400 focus:border-ink-900 focus:shadow-[0_0_0_3px_var(--color-brand-500)] focus:outline-none focus-visible:outline-none disabled:border-stone-200 disabled:bg-stone-100 disabled:text-stone-500';

export function Input({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...rest} className={cx(CONTROL, 'h-10', className)} />;
}

export function Textarea({ className, ...rest }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...rest} className={cx(CONTROL, 'py-2', className)} />;
}

export function Select({ className, children, ...rest }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select {...rest} className={cx(CONTROL, 'h-10 pr-8', className)}>
      {children}
    </select>
  );
}

export function Checkbox({ label, ...rest }: InputHTMLAttributes<HTMLInputElement> & { label: ReactNode }) {
  return (
    <label className="inline-flex cursor-pointer items-center gap-2 text-sm font-medium text-ink-900">
      <input type="checkbox" {...rest} className="size-4 rounded-sm border-2 border-ink-900 accent-ink-900" />
      {label}
    </label>
  );
}

export function Field({ label, hint, children, className }: { label: string; hint?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <label className={cx('block', className)}>
      <span className="mb-1.5 block text-sm font-bold text-ink-900">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-stone-500">{hint}</span>}
    </label>
  );
}

// ── Layout pieces ─────────────────────────────────────────────────────────────

export function PageHeader({ title, description, actions }: { title: string; description?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        {/* Short yellow bar: the page's anchor point, same mark as the active menu item. */}
        <div aria-hidden className="mb-2 h-1.5 w-10 bg-brand-500" />
        <h1 className="text-2xl font-extrabold tracking-tight text-ink-900">{title}</h1>
        {description && <p className="mt-1 max-w-3xl text-sm text-stone-500">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

export function Card({ title, actions, children, className }: { title?: ReactNode; actions?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={cx('rounded-lg border-2 border-stone-200 bg-white', className)}>
      {(title || actions) && (
        <div className="flex items-center justify-between gap-2 border-b-2 border-stone-200 px-4 py-3">
          <h2 className="text-base font-extrabold text-ink-900">{title}</h2>
          {actions}
        </div>
      )}
      <div className="p-4">{children}</div>
    </section>
  );
}

export function Toolbar({ children }: { children: ReactNode }) {
  return <div className="mb-4 flex flex-wrap items-end gap-3">{children}</div>;
}

// Flat badges: tinted fill + matching border + bold text, all at 7:1 or better.
const TONES = {
  gray: 'border-stone-300 bg-stone-100 text-stone-700',
  green: 'border-green-300 bg-green-50 text-green-800',
  red: 'border-red-300 bg-red-50 text-red-800',
  amber: 'border-amber-300 bg-amber-50 text-amber-900',
  blue: 'border-blue-300 bg-blue-50 text-blue-800',
  gold: 'border-brand-500 bg-brand-500 text-ink-900',
} as const;
export type Tone = keyof typeof TONES;

export function Badge({ tone = 'gray', children }: { tone?: Tone; children: ReactNode }) {
  return <span className={cx('inline-flex items-center rounded border px-2 py-0.5 text-xs font-bold whitespace-nowrap', TONES[tone])}>{children}</span>;
}

export function Stat({ label, value, hint }: { label: string; value: ReactNode; hint?: ReactNode }) {
  return (
    <div className="rounded-lg border-2 border-stone-200 border-t-brand-500 bg-white p-4">
      <div className="text-xs font-bold tracking-wide text-stone-500 uppercase">{label}</div>
      {/* Large amounts wrap instead of being cut off; no money figure is ever truncated. */}
      <div className="num mt-1 text-lg font-extrabold [overflow-wrap:anywhere] text-ink-900 sm:text-xl xl:text-2xl">{value}</div>
      {hint && <div className="mt-1 text-xs text-stone-500">{hint}</div>}
    </div>
  );
}

// ── Table ─────────────────────────────────────────────────────────────────────

export interface Column<T> {
  header: ReactNode;
  cell: (row: T) => ReactNode;
  align?: 'left' | 'right' | 'center';
  className?: string;
  /** Free text (notes, addresses): wraps. Every other column stays on one line and the table scrolls. */
  wrap?: boolean;
}

export function DataTable<T>({
  columns,
  rows,
  rowKey,
  onRowClick,
  empty = 'Tidak ada data',
  footer,
}: {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string | number;
  onRowClick?: (row: T) => void;
  empty?: ReactNode;
  footer?: ReactNode;
}) {
  const align = (a?: 'left' | 'right' | 'center') => (a === 'right' ? 'text-right' : a === 'center' ? 'text-center' : 'text-left');
  return (
    <div className="overflow-x-auto rounded-lg border-2 border-ink-900 bg-white">
      <table className="w-full text-sm">
        <thead className="bg-ink-900 text-xs tracking-wide text-white uppercase">
          <tr>
            {columns.map((c, i) => (
              <th key={i} scope="col" className={cx('px-3 py-3 font-bold whitespace-nowrap', align(c.align), c.className)}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-stone-200">
          {rows.length === 0 ? (
            <tr>
              <td colSpan={columns.length} className="px-3 py-12 text-center font-medium text-stone-500">
                {empty}
              </td>
            </tr>
          ) : (
            rows.map((row) => (
              <tr
                key={rowKey(row)}
                onClick={onRowClick ? () => onRowClick(row) : undefined}
                className={cx('even:bg-stone-50', onRowClick && 'cursor-pointer hover:bg-brand-100 even:hover:bg-brand-100')}
              >
                {columns.map((c, i) => (
                  <td key={i} className={cx('px-3 py-2.5 align-top', c.wrap ? 'min-w-56 whitespace-normal' : 'whitespace-nowrap', align(c.align), c.align === 'right' && 'num', c.className)}>
                    {c.cell(row)}
                  </td>
                ))}
              </tr>
            ))
          )}
        </tbody>
        {footer && <tfoot className="border-t-2 border-ink-900 bg-brand-50 font-bold">{footer}</tfoot>}
      </table>
    </div>
  );
}

export function Pagination({ page, totalPages, onChange }: { page: number; totalPages: number; onChange: (page: number) => void }) {
  if (totalPages <= 1) return null;
  return (
    <div className="mt-3 flex items-center justify-end gap-3 text-sm font-medium text-ink-900">
      <Button size="sm" disabled={page <= 1} onClick={() => onChange(page - 1)}>
        Sebelumnya
      </Button>
      <span>
        Halaman {page} dari {totalPages}
      </span>
      <Button size="sm" disabled={page >= totalPages} onClick={() => onChange(page + 1)}>
        Berikutnya
      </Button>
    </div>
  );
}

// ── States ────────────────────────────────────────────────────────────────────

export function Spinner({ className }: { className?: string }) {
  return <Loader2 aria-label="Memuat" className={cx('size-6 animate-spin text-ink-900', className)} />;
}

export function ErrorBox({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  return (
    <div role="alert" className="flex items-start gap-3 rounded-lg border-2 border-red-600 bg-red-50 p-4 text-sm font-medium text-red-800">
      <AlertTriangle className="mt-0.5 size-4 shrink-0" />
      <div className="flex-1">{errorMessage(error)}</div>
      {onRetry && (
        <Button size="sm" onClick={onRetry}>
          Coba lagi
        </Button>
      )}
    </div>
  );
}

/** Loading / error wrapper for a query result. */
export function QueryState({ query, children }: { query: { isPending: boolean; error: unknown; refetch: () => unknown }; children: ReactNode }) {
  if (query.isPending) {
    return (
      <div className="flex justify-center py-16">
        <Spinner />
      </div>
    );
  }
  if (query.error) return <ErrorBox error={query.error} onRetry={() => query.refetch()} />;
  return <>{children}</>;
}

// ── Modal ─────────────────────────────────────────────────────────────────────

export function Modal({
  open,
  onClose,
  title,
  children,
  footer,
  wide,
}: {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  children: ReactNode;
  footer?: ReactNode;
  wide?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      className={cx('m-auto w-[calc(100%-2rem)] rounded-lg border-2 border-ink-900 bg-white p-0', wide ? 'max-w-4xl' : 'max-w-lg')}
    >
      {open && (
        <div className="flex max-h-[85vh] flex-col">
          <div className="flex items-center justify-between border-b-2 border-ink-900 bg-brand-500 px-5 py-3">
            <h2 className="text-base font-extrabold text-ink-900">{title}</h2>
            <button type="button" onClick={onClose} className="rounded-md p-1.5 text-ink-900 hover:bg-ink-900 hover:text-brand-500" aria-label="Tutup">
              <X className="size-5" />
            </button>
          </div>
          <div className="overflow-y-auto px-5 py-4">{children}</div>
          {footer && <div className="flex justify-end gap-2 border-t-2 border-stone-200 bg-stone-50 px-5 py-3">{footer}</div>}
        </div>
      )}
    </dialog>
  );
}

/** A button that asks for confirmation in a modal, then runs `onConfirm`. */
export function ConfirmButton({
  label,
  title,
  message,
  confirmLabel = 'Ya, lanjutkan',
  variant = 'secondary',
  confirmVariant = 'danger',
  size,
  icon,
  disabled,
  onConfirm,
}: {
  label: ReactNode;
  title: string;
  message: ReactNode;
  confirmLabel?: string;
  variant?: Variant;
  confirmVariant?: Variant;
  size?: 'sm' | 'md';
  icon?: ReactNode;
  disabled?: boolean;
  onConfirm: () => Promise<unknown>;
}) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  return (
    <>
      <Button variant={variant} size={size} icon={icon} disabled={disabled} onClick={() => setOpen(true)}>
        {label}
      </Button>
      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title={title}
        footer={
          <>
            <Button onClick={() => setOpen(false)}>Batal</Button>
            <Button
              variant={confirmVariant}
              loading={busy}
              onClick={async () => {
                setBusy(true);
                try {
                  await onConfirm();
                  setOpen(false);
                } catch (error) {
                  toast.error(errorMessage(error));
                } finally {
                  setBusy(false);
                }
              }}
            >
              {confirmLabel}
            </Button>
          </>
        }
      >
        <div className="text-sm text-ink-900">{message}</div>
      </Modal>
    </>
  );
}

// ── Toasts ────────────────────────────────────────────────────────────────────

interface Toast {
  id: number;
  tone: 'success' | 'error';
  text: string;
}
interface ToastApi {
  success: (text: string) => void;
  error: (text: string) => void;
}
const ToastContext = createContext<ToastApi | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const push = useCallback((tone: Toast['tone'], text: string) => {
    const id = Date.now() + Math.random();
    setToasts((t) => [...t, { id, tone, text }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), tone === 'error' ? 7000 : 3500);
  }, []);
  const [value] = useState<ToastApi>(() => ({ success: (t) => push('success', t), error: (t) => push('error', t) }));

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="pointer-events-none fixed right-4 bottom-4 z-50 flex w-80 flex-col gap-2">
        {toasts.map((t) => (
          <div
            key={t.id}
            role="status"
            className={cx(
              'pointer-events-auto rounded-md border-l-8 px-4 py-3 text-sm font-bold',
              t.tone === 'success' ? 'border-brand-500 bg-ink-900 text-white' : 'border-red-900 bg-red-600 text-white',
            )}
          >
            {t.text}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastApi {
  const value = useContext(ToastContext);
  if (!value) throw new Error('useToast outside ToastProvider');
  return value;
}
